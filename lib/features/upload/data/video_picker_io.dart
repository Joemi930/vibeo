import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'video_compressor.dart';
import 'video_picker.dart';

/// Sélection mobile : galerie du système via `image_picker`.
///
/// `image_picker` passe par le sélecteur de médias d'Android (aucune
/// permission à demander depuis Android 13) et renvoie un chemin disque, ce
/// dont `video_compress` a besoin.
class NativeVideoPicker implements VideoPicker {
  @override
  Future<VideoSource?> pickVideo() async {
    final XFile? file;
    try {
      file = await ImagePicker().pickVideo(source: ImageSource.gallery);
    } on PlatformException catch (error) {
      throw PickerException(_message(error));
    }
    if (file == null) return null;

    final length = await File(file.path).length();
    return VideoSource(name: file.name, sizeBytes: length, path: file.path);
  }

  static String _message(PlatformException error) {
    if (error.code == 'photo_access_denied') {
      return 'Vibeo n\'a pas accès à tes vidéos. '
          'Autorise l\'accès dans les réglages du téléphone.';
    }
    return 'Impossible d\'ouvrir ce fichier. Réessaie.';
  }
}

VideoPicker createVideoPicker() => NativeVideoPicker();
