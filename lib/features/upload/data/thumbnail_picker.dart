import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../../../core/constants/media_limits.dart';
import 'video_picker.dart';

/// Image choisie par l'artiste pour remplacer la miniature extraite du clip.
class PickedThumbnail {
  const PickedThumbnail({
    required this.bytes,
    required this.fileExtension,
    required this.contentType,
  });

  final Uint8List bytes;
  final String fileExtension;
  final String contentType;
}

/// Ouvre la galerie pour choisir une image (miniature de clip, avatar,
/// bannière de profil…).
///
/// `image_picker` fonctionne aussi bien sur Android que sur le web : une seule
/// implémentation suffit ici, contrairement à la sélection de clip.
///
/// [maxWidth] et [maxBytes] sont paramétrables pour que chaque appelant
/// applique le plafond qui lui correspond (une miniature de clip, un avatar et
/// une bannière n'ont pas les mêmes contraintes) sans dupliquer la logique de
/// détection du type MIME et de vérification de taille — c'est cette
/// duplication qui, avant, faisait deviner le type (un `.gif` partait par
/// exemple en `image/jpeg`) et sautait la vérification de taille côté
/// `profile_screen.dart`.
///
/// Renvoie `null` si l'utilisateur annule. Lève [PickerException] si l'image
/// dépasse le plafond ou n'est pas d'un type accepté — les mêmes règles que
/// celles appliquées par le bucket Storage.
Future<PickedThumbnail?> pickThumbnailImage({
  double maxWidth = 1920,
  int maxBytes = MediaLimits.maxThumbnailBytes,
}) async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    // Ignoré sur le web, appliqué sur Android : évite d'envoyer une photo de
    // 12 Mpx pour une vignette.
    maxWidth: maxWidth,
    imageQuality: 85,
  );
  if (file == null) return null;

  final extension = _extensionOf(file.name);
  final contentType = _contentTypes[extension];
  if (contentType == null) {
    throw const PickerException('Choisis une image JPEG, PNG ou WebP.');
  }

  final bytes = await file.readAsBytes();
  if (bytes.length > maxBytes) {
    throw PickerException(
      'Cette image pèse ${MediaLimits.formatBytes(bytes.length)}. '
      'La limite est de ${MediaLimits.formatBytes(maxBytes)}.',
    );
  }

  return PickedThumbnail(
    bytes: bytes,
    fileExtension: extension,
    contentType: contentType,
  );
}

const Map<String, String> _contentTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
};

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot == -1 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}
