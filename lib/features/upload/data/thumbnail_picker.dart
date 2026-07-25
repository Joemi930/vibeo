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

/// Ouvre la galerie pour choisir une miniature personnalisée.
///
/// `image_picker` fonctionne aussi bien sur Android que sur le web : une seule
/// implémentation suffit ici, contrairement à la sélection de clip.
///
/// Renvoie `null` si l'utilisateur annule. Lève [PickerException] si l'image
/// dépasse le plafond ou n'est pas d'un type accepté — les mêmes règles que
/// celles appliquées par le bucket Storage.
Future<PickedThumbnail?> pickThumbnailImage() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    // Ignoré sur le web, appliqué sur Android : évite d'envoyer une photo de
    // 12 Mpx pour une vignette.
    maxWidth: 1920,
    imageQuality: 85,
  );
  if (file == null) return null;

  final extension = _extensionOf(file.name);
  final contentType = _contentTypes[extension];
  if (contentType == null) {
    throw const PickerException('Choisis une image JPEG, PNG ou WebP.');
  }

  final bytes = await file.readAsBytes();
  if (bytes.length > MediaLimits.maxThumbnailBytes) {
    throw PickerException(
      'Cette image pèse ${MediaLimits.formatBytes(bytes.length)}. '
      'La limite est de '
      '${MediaLimits.formatBytes(MediaLimits.maxThumbnailBytes)}.',
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
