import 'video_compressor.dart';
import 'video_picker_io.dart'
    if (dart.library.js_interop) 'video_picker_web.dart'
    as impl;

/// Erreur de sélection de fichier, porteuse d'un message affichable tel quel.
class PickerException implements Exception {
  const PickerException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Ouvre le sélecteur de fichiers de la plateforme.
///
/// Remplace `file_picker`, dont la version compatible avec ce projet ne
/// fonctionnait plus sur le web. Chaque plateforme utilise désormais le chemin
/// le plus court vers le fichier :
/// - mobile : `image_picker`, qui donne un chemin disque exploitable par les
///   encodeurs natifs ;
/// - web : un `<input type="file">` géré dans `web/js/vibeo_media.js`, qui
///   garde le fichier côté JavaScript pour ne pas le charger en mémoire Dart.
abstract class VideoPicker {
  /// Renvoie le clip choisi, ou `null` si l'utilisateur a annulé.
  ///
  /// Lève [PickerException] si la sélection échoue pour une raison
  /// présentable à l'utilisateur.
  Future<VideoSource?> pickVideo();
}

/// Fabrique l'implémentation adaptée à la plateforme courante.
VideoPicker createVideoPicker() => impl.createVideoPicker();
