import 'dart:typed_data';

import 'video_compressor_io.dart'
    if (dart.library.js_interop) 'video_compressor_web.dart'
    as impl;

/// Fichier vidéo choisi par l'utilisateur, avant traitement.
///
/// Volontairement dépourvu des octets du fichier : un clip peut peser plusieurs
/// centaines de mégaoctets, et les charger en mémoire faisait échouer la
/// sélection sur le web. Chaque plateforme garde donc une **référence** au
/// fichier plutôt que son contenu :
/// - mobile : [path], un chemin sur le disque lu par les encodeurs natifs ;
/// - web : [webHandle], un identifiant opaque désignant un `File` resté côté
///   JavaScript (voir `web/js/vibeo_media.js`).
///
/// Seul le résultat compressé transite ensuite par la mémoire Dart.
class VideoSource {
  const VideoSource({
    required this.name,
    required this.sizeBytes,
    this.path,
    this.webHandle,
    this.durationSeconds,
    this.width,
    this.height,
  });

  final String name;
  final int sizeBytes;

  /// Chemin disque du fichier (mobile et bureau uniquement).
  final String? path;

  /// Identifiant du `File` conservé côté JavaScript (web uniquement).
  final int? webHandle;

  /// Métadonnées lues à la sélection quand la plateforme le permet (web).
  final int? durationSeconds;
  final int? width;
  final int? height;

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

  /// Miniature extraite du clip, en JPEG.
  ///
  /// Reste `null` si l'extraction a échoué : une miniature manquante ne doit
  /// jamais empêcher une publication, l'interface propose alors de choisir une
  /// image et retombe sinon sur un visuel de remplacement.
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
/// miniature.
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

  /// Vrai si la plateforme sait réellement compresser.
  ///
  /// Le web répond désormais oui dès que l'encodeur H.264 du navigateur est
  /// disponible (Chrome, Edge, Safari) — c'est faux sur Firefox, qui annonce
  /// l'API WebCodecs sans savoir encoder.
  Future<bool> get supportsCompression;
}

/// Fabrique l'implémentation adaptée à la plateforme courante.
///
/// L'import conditionnel garantit que `video_compress` (qui dépend de
/// `dart:io`) n'est jamais compilé pour le web, et réciproquement que le pont
/// `dart:js_interop` n'est jamais compilé pour Android.
VideoCompressor createVideoCompressor() => impl.createVideoCompressor();
