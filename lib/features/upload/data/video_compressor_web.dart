import 'dart:typed_data';

import '../../../core/constants/media_limits.dart';
import 'video_compressor.dart';
import 'web/vibeo_media_interop.dart' as js;

/// Implémentation web : compression H.264 720p **dans le navigateur**.
///
/// Contrairement à ce que supposait l'architecture initiale, le web sait
/// compresser : l'API **WebCodecs** donne accès à l'encodeur matériel de la
/// machine. Le calcul reste donc chez l'utilisateur — aucun transcodage
/// serveur, conformément au budget 0 €.
///
/// Le fichier d'origine ne quitte jamais le côté JavaScript : on lui envoie un
/// identifiant et on récupère seulement le MP4 compressé et la miniature. Sans
/// cela, un clip de 400 Mo devrait d'abord tenir en mémoire Dart.
///
/// Firefox annonce l'API WebCodecs mais échoue à l'encodage H.264 : la
/// détection se fait donc par `canEncodeVideo`, pas par la présence de l'API.
class WebVideoCompressor implements VideoCompressor {
  Future<bool>? _canEncode;

  @override
  Future<bool> get supportsCompression {
    if (!js.isMediaBridgeReady) return Future.value(false);
    return _canEncode ??= js.canEncodeH264();
  }

  @override
  Future<CompressedVideo> compress(
    VideoSource source, {
    void Function(double progress)? onProgress,
  }) async {
    if (!js.isMediaBridgeReady) {
      throw const CompressionException(
        'Le module de préparation vidéo n\'a pas pu être chargé. '
        'Recharge la page.',
      );
    }

    final handle = source.webHandle;
    if (handle == null) {
      throw const CompressionException(
        'Fichier introuvable. Choisis à nouveau ta vidéo.',
      );
    }

    // Refus avant tout calcul : inutile de réencoder quatre minutes pour
    // annoncer ensuite que le clip est trop long.
    final duration = source.durationSeconds;
    if (duration != null && duration > MediaLimits.maxVideoDuration.inSeconds) {
      throw CompressionException(
        'Ce clip dure ${MediaLimits.formatDuration(Duration(seconds: duration))}. '
        'La limite est de ${MediaLimits.maxVideoDuration.inMinutes} minutes.',
      );
    }

    final bytes = await _encodeOrPassThrough(
      handle: handle,
      sourceSize: source.sizeBytes,
      onProgress: onProgress,
    );

    final thumbnail = await _extractThumbnail(handle, duration);

    onProgress?.call(1);
    return CompressedVideo(
      bytes: bytes,
      originalSizeBytes: source.sizeBytes,
      fileExtension: 'mp4',
      contentType: 'video/mp4',
      durationSeconds: duration != null && duration > 0 ? duration : null,
      thumbnailBytes: thumbnail,
    );
  }

  /// Réencode le clip, ou l'envoie tel quel si le navigateur ne sait pas
  /// encoder et que le fichier tient déjà sous le plafond.
  Future<Uint8List> _encodeOrPassThrough({
    required int handle,
    required int sourceSize,
    void Function(double progress)? onProgress,
  }) async {
    if (!await supportsCompression) {
      if (sourceSize <= MediaLimits.maxVideoBytes) {
        final original = await js.readOriginalFile(handle);
        final bytes = js.bytesOf(original);
        if (bytes != null) return bytes;
      }
      throw CompressionException(
        'Ce navigateur ne sait pas compresser de vidéo. '
        'Utilise Chrome, Edge ou Safari, ou publie depuis l\'application '
        'Android — ou choisis un clip de moins de '
        '${MediaLimits.formatBytes(MediaLimits.maxVideoBytes)}.',
      );
    }

    // Une seule reprise, à débit réduit : au-delà, mieux vaut le dire que
    // faire patienter l'artiste pour rien.
    for (final quality in const ['medium', 'low']) {
      final result = await js.compressVideoFile(
        handle: handle,
        maxHeight: 720,
        quality: quality,
        onProgress: onProgress == null
            ? null
            : (progress) => onProgress(progress.clamp(0.0, 0.98)),
      );

      if (result.status != 'ok') {
        throw CompressionException(
          result.message ??
              'La préparation du clip a échoué. Réessaie avec une autre vidéo.',
        );
      }

      final bytes = js.bytesOf(result);
      if (bytes == null) {
        throw const CompressionException(
          'La préparation du clip a échoué. Réessaie avec une autre vidéo.',
        );
      }
      if (bytes.length <= MediaLimits.maxVideoBytes) return bytes;
    }

    throw CompressionException(
      'Même compressé, ce clip dépasse '
      '${MediaLimits.formatBytes(MediaLimits.maxVideoBytes)}. '
      'Raccourcis-le puis réessaie.',
    );
  }

  /// Miniature prise à 10 % de la durée : évite les premières images souvent
  /// noires. Même règle que sur Android.
  Future<Uint8List?> _extractThumbnail(int handle, int? durationSeconds) async {
    final at = durationSeconds != null && durationSeconds > 0
        ? durationSeconds * 0.1
        : 0.0;
    final result = await js.grabThumbnail(handle: handle, atSeconds: at);
    if (result.status != 'ok') return null;
    return js.bytesOf(result);
  }

  @override
  Future<void> cancel() async {
    // Rien à faire : `Conversion` n'est pas interrompue en cours de route, et
    // la remise à zéro de l'écran suffit à ignorer son résultat.
  }
}

VideoCompressor createVideoCompressor() => WebVideoCompressor();
