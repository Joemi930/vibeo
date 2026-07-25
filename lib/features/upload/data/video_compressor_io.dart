import 'dart:io';
import 'dart:typed_data';

import 'package:video_compress/video_compress.dart';

import '../../../core/constants/media_limits.dart';
import 'video_compressor.dart';

/// Implémentation mobile/desktop : compression H.264 720p **sur l'appareil**.
///
/// C'est le pilier de la stratégie « budget 0 € » : aucun transcodage serveur,
/// donc aucun coût de calcul. `video_compress` s'appuie sur les encodeurs
/// natifs (MediaCodec sur Android, AVFoundation sur iOS) plutôt que sur des
/// binaires FFmpeg embarqués — l'APK reste léger et le projet FFmpegKit,
/// retiré en 2025, n'est plus une dépendance.
class NativeVideoCompressor implements VideoCompressor {
  Subscription? _progressSubscription;

  @override
  Future<bool> get supportsCompression async => true;

  @override
  Future<CompressedVideo> compress(
    VideoSource source, {
    void Function(double progress)? onProgress,
  }) async {
    final path = source.path;
    if (path == null) {
      throw const CompressionException(
        'Fichier introuvable. Choisis à nouveau ta vidéo.',
      );
    }

    final info = await VideoCompress.getMediaInfo(path);
    final durationMs = info.duration ?? 0;
    final durationSeconds = (durationMs / 1000).round();

    if (durationSeconds > MediaLimits.maxVideoDuration.inSeconds) {
      throw CompressionException(
        'Ce clip dure ${MediaLimits.formatDuration(Duration(seconds: durationSeconds))}. '
        'La limite est de ${MediaLimits.maxVideoDuration.inMinutes} minutes.',
      );
    }

    _progressSubscription?.unsubscribe();
    _progressSubscription = VideoCompress.compressProgress$.subscribe(
      (progress) => onProgress?.call((progress / 100).clamp(0, 1)),
    );

    try {
      final compressed = await VideoCompress.compressVideo(
        path,
        quality: VideoQuality.Res1280x720Quality,
        includeAudio: true,
        deleteOrigin: false,
      );

      final compressedPath = compressed?.path;
      if (compressedPath == null) {
        throw const CompressionException(
          'La compression a échoué. Réessaie avec une autre vidéo.',
        );
      }

      final bytes = await File(compressedPath).readAsBytes();
      if (bytes.length > MediaLimits.maxVideoBytes) {
        throw CompressionException(
          'Même compressé, ce clip pèse ${MediaLimits.formatBytes(bytes.length)}. '
          'La limite est de ${MediaLimits.formatBytes(MediaLimits.maxVideoBytes)}.',
        );
      }

      // Miniature prise à 10 % de la durée : évite les premières images
      // souvent noires.
      final thumbnail = await _extractThumbnail(path, durationSeconds);

      onProgress?.call(1);
      return CompressedVideo(
        bytes: bytes,
        originalSizeBytes: source.sizeBytes,
        fileExtension: 'mp4',
        contentType: 'video/mp4',
        durationSeconds: durationSeconds > 0 ? durationSeconds : null,
        thumbnailBytes: thumbnail,
      );
    } finally {
      _progressSubscription?.unsubscribe();
      _progressSubscription = null;
    }
  }

  Future<Uint8List?> _extractThumbnail(String path, int durationSeconds) async {
    try {
      return await VideoCompress.getByteThumbnail(
        path,
        quality: 75,
        position: durationSeconds > 0 ? (durationSeconds * 100) : -1,
      );
    } catch (_) {
      // Une miniature manquante ne doit pas faire échouer une publication :
      // l'interface retombe sur un visuel de remplacement.
      return null;
    }
  }

  @override
  Future<void> cancel() async {
    _progressSubscription?.unsubscribe();
    _progressSubscription = null;
    await VideoCompress.cancelCompression();
  }
}

VideoCompressor createVideoCompressor() => NativeVideoCompressor();
