import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/dev_log.dart';

import '../../../upload/data/thumbnail_picker.dart';
import '../../../upload/data/video_picker.dart';
import '../../../video/domain/video.dart';
import '../../../video/presentation/providers/video_providers.dart';

/// État de l'écran de modification d'un clip.
@immutable
class EditVideoState {
  const EditVideoState({
    this.thumbnail,
    this.isSaving = false,
    this.errorMessage,
  });

  /// Nouvelle miniature choisie, pas encore envoyée.
  final PickedThumbnail? thumbnail;
  final bool isSaving;
  final String? errorMessage;

  EditVideoState copyWith({
    PickedThumbnail? thumbnail,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    bool clearThumbnail = false,
  }) {
    return EditVideoState(
      thumbnail: clearThumbnail ? null : (thumbnail ?? this.thumbnail),
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Modification d'un clip déjà publié : titre, description, genre, miniature.
///
/// Le fichier vidéo lui-même n'est jamais remplacé — republier serait plus sain
/// que de changer le contenu sous une fiche qui a déjà des vues et des likes.
class EditVideoController extends Notifier<EditVideoState> {
  @override
  EditVideoState build() => const EditVideoState();

  Future<void> chooseThumbnail() async {
    try {
      final picked = await pickThumbnailImage();
      if (picked == null) return;
      state = state.copyWith(thumbnail: picked, clearError: true);
    } on PickerException catch (e) {
      state = state.copyWith(errorMessage: e.message);
    } catch (error, stack) {
      logError('choix de miniature impossible', error, stack);
      state = state.copyWith(
        errorMessage: 'Impossible d\'ouvrir cette image. Réessaie.',
      );
    }
  }

  /// Revient à la miniature déjà en ligne.
  void keepCurrentThumbnail() =>
      state = state.copyWith(clearThumbnail: true, clearError: true);

  /// Enregistre les modifications. Renvoie `true` en cas de succès.
  Future<bool> save({
    required Video video,
    required String title,
    String? description,
    int? genreId,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    final repo = ref.read(videoRepositoryProvider);
    final previousThumbnail = video.thumbnailPath;

    try {
      String? thumbnailPath;
      final picked = state.thumbnail;
      if (picked != null) {
        thumbnailPath = await repo.uploadThumbnail(
          userId: video.artistId,
          videoId: video.id,
          bytes: picked.bytes,
          fileExtension: picked.fileExtension,
          contentType: picked.contentType,
        );
      }

      final updated = await repo.updateVideo(
        videoId: video.id,
        title: title.trim(),
        description: description?.trim(),
        genreId: genreId,
        thumbnailPath: thumbnailPath,
        clearDescription: description == null || description.trim().isEmpty,
        clearGenre: genreId == null,
      );

      // Le remplaçant peut porter une autre extension (.png après un .jpg) :
      // sans ce nettoyage, l'ancien fichier resterait à consommer du quota.
      if (thumbnailPath != null &&
          previousThumbnail != null &&
          previousThumbnail.isNotEmpty &&
          previousThumbnail != thumbnailPath) {
        try {
          await repo.removeThumbnailFile(previousThumbnail);
        } catch (error) {
          logError('ancienne miniature non supprimée', error);
        }
      }

      ref.invalidate(publishedVideosProvider);
      ref.invalidate(studioVideosProvider(video.artistId));
      ref.invalidate(videoByIdProvider(video.id));
      ref.invalidate(thumbnailUrlProvider(updated.thumbnailPath));

      state = state.copyWith(isSaving: false, clearThumbnail: true);
      return true;
    } catch (error, stack) {
      logError('modification impossible', error, stack);
      state = state.copyWith(isSaving: false, errorMessage: _saveError(error));
      return false;
    }
  }

  static String _saveError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('row-level security') || raw.contains('42501')) {
      return 'Tu ne peux modifier que tes propres clips.';
    }
    return 'L\'enregistrement a échoué. Vérifie ta connexion et réessaie.';
  }
}

final editVideoControllerProvider =
    NotifierProvider<EditVideoController, EditVideoState>(
      EditVideoController.new,
    );
