import 'dart:typed_data';

import 'video_compressor_io.dart'
    if (dart.library.js_interop) 'video_compressor_web.dart'
    as impl;

/// Fichier vidéo choisi par l'utilisateur, avant traitement.
///
/// Sur mobile on dispose d'un chemin de fichier ; sur le web, uniquement des
/// octets en mémoire.
class VideoSource {
  const VideoSource({
    required this.name,
    required this.sizeBytes,
    this.path,
    this.bytes,
  });

  final String name;
  final int sizeBytes;
  final String? path;
  final Uint8List? bytes;

  /// Extension en minuscules, sans le point (`mp4` par défaut).
  String get fileExtension {
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return 'mp4';
    return name.substring(dot + 1).toLowerCase();
  }
}

/// Résultat d'une préparation de clip, prêt à être téléversé.
class CompressedVideo {
  const CompressedVideo({
    required this.bytes,
    required this.originalSizeBytes,
    required this.fileExtension,
    required this.contentType,
    this.durationSeconds,
    this.thumbnailBytes,
  });

  final Uint8List bytes;
  final int originalSizeBytes;
  final String fileExtension;
  final String contentType;
  final int? durationSeconds;

  /// Miniature extraite du clip (null sur le web, où l'extraction n'est pas
  /// disponible : l'interface affiche alors un visuel de remplacement).
  final Uint8List? thumbnailBytes;

  int get sizeBytes => bytes.length;

  /// Vrai si la compression a réellement réduit le fichier.
  bool get wasCompressed => sizeBytes < originalSizeBytes;

  /// Gain en pourcentage, pour l'affichage « avant → après ».
  double get savedRatio => originalSizeBytes == 0
      ? 0
      : (originalSizeBytes - sizeBytes) / originalSizeBytes;
}

/// Erreur de préparation d'un clip, porteuse d'un message affichable tel quel.
class CompressionException implements Exception {
  const CompressionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Prépare un clip pour l'upload : compression H.264 720p et extraction de la
/// miniature quand la plateforme le permet.
abstract class VideoCompressor {
  /// Compresse [source] et extrait sa miniature.
  ///
  /// [onProgress] reçoit une valeur entre 0 et 1. Lève [CompressionException]
  /// si le fichier dépasse les plafonds ou si le traitement échoue.
  Future<CompressedVideo> compress(
    VideoSource source, {
    void Function(double progress)? onProgress,
  });

  /// Annule une compression en cours, si la plateforme le permet.
  Future<void> cancel();

  /// Vrai si la plateforme sait réellement compresser (faux sur le web).
  bool get supportsCompression;
}

/// Fabrique l'implémentation adaptée à la plateforme courante.
///
/// L'import conditionnel garantit que `video_compress` (qui dépend de
/// `dart:io`) n'est jamais compilé pour le web.
VideoCompressor createVideoCompressor() => impl.createVideoCompressor();
