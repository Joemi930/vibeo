import '../../../core/constants/media_limits.dart';
import 'video_compressor.dart';

/// Implémentation web : **aucune compression possible dans un navigateur**.
///
/// Les encodeurs natifs ne sont pas accessibles depuis le web. Le fichier est
/// donc envoyé tel quel, et refusé au-delà du plafond avec un message explicite
/// invitant à publier depuis Android — c'est le parcours prévu par
/// l'architecture (« publication surtout depuis Android »).
class WebVideoCompressor implements VideoCompressor {
  @override
  bool get supportsCompression => false;

  @override
  Future<CompressedVideo> compress(
    VideoSource source, {
    void Function(double progress)? onProgress,
  }) async {
    final bytes = source.bytes;
    if (bytes == null) {
      throw const CompressionException(
        'Fichier illisible. Choisis à nouveau ta vidéo.',
      );
    }

    if (bytes.length > MediaLimits.maxVideoBytes) {
      throw CompressionException(
        'Ce clip pèse ${MediaLimits.formatBytes(bytes.length)}. '
        'Depuis un navigateur, la compression n\'est pas disponible : '
        'la limite est de ${MediaLimits.formatBytes(MediaLimits.maxVideoBytes)}. '
        'Publie depuis l\'application Android pour les fichiers plus lourds.',
      );
    }

    onProgress?.call(1);
    return CompressedVideo(
      bytes: bytes,
      originalSizeBytes: source.sizeBytes,
      fileExtension: source.fileExtension == 'mov' ? 'mov' : 'mp4',
      contentType: source.fileExtension == 'mov'
          ? 'video/quicktime'
          : 'video/mp4',
      // Pas d'extraction de miniature sur le web : l'interface affiche un
      // visuel de remplacement.
      thumbnailBytes: null,
    );
  }

  @override
  Future<void> cancel() async {}
}

VideoCompressor createVideoCompressor() => WebVideoCompressor();
