import 'video_compressor.dart';
import 'video_picker.dart';
import 'web/vibeo_media_interop.dart' as js;

/// Sélection web : `<input type="file">` géré côté JavaScript.
///
/// Le fichier reste dans le navigateur ; Dart n'en reçoit qu'un identifiant et
/// les métadonnées (nom, taille, durée, dimensions). Lire les octets ici
/// faisait échouer la sélection sur les gros fichiers.
class WebVideoPicker implements VideoPicker {
  @override
  Future<VideoSource?> pickVideo() async {
    if (!js.isMediaBridgeReady) {
      throw const PickerException(
        'Le module de préparation vidéo n\'a pas pu être chargé. '
        'Recharge la page.',
      );
    }

    final result = await js.pickVideoFile();
    switch (result.status) {
      case 'cancelled':
        return null;
      case 'ok':
        final handle = result.handle;
        if (handle == null) {
          throw const PickerException(
            'Impossible d\'ouvrir ce fichier. Réessaie.',
          );
        }
        if (result.decodable == false) {
          js.releaseHandle(handle);
          throw const PickerException(
            'Ce navigateur ne sait pas lire cette vidéo : son format ou son '
            'profil d\'encodage n\'est pas pris en charge.',
          );
        }
        return VideoSource(
          name: result.name ?? 'clip.mp4',
          sizeBytes: result.size ?? 0,
          webHandle: handle,
          durationSeconds: result.durationSeconds,
          width: result.width,
          height: result.height,
        );
      default:
        throw PickerException(
          result.message ?? 'Impossible d\'ouvrir ce fichier. Réessaie.',
        );
    }
  }
}

VideoPicker createVideoPicker() => WebVideoPicker();
