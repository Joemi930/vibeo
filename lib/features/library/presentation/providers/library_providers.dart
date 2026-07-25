import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/dev_log.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../video/domain/video.dart';
import '../../data/playlist_repository.dart';
import '../../domain/playlist.dart';

final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  return SupabasePlaylistRepository(ref.watch(supabaseClientProvider));
});

/// Playlists de l'utilisateur courant (onglet Playlists).
final myPlaylistsProvider = FutureProvider<List<Playlist>>((ref) {
  return ref.watch(playlistRepositoryProvider).fetchMine();
});

/// Une playlist précise, pour son écran de détail.
final playlistByIdProvider = FutureProvider.family<Playlist?, String>((
  ref,
  playlistId,
) {
  return ref.watch(playlistRepositoryProvider).fetchById(playlistId);
});

/// Historique de lecture (onglet Historique), dédoublonné par clip.
final watchHistoryProvider = FutureProvider<List<Video>>((ref) {
  return ref.watch(playlistRepositoryProvider).fetchHistory();
});

/// Contenu ordonné d'une playlist, avec réordonnancement optimiste.
class PlaylistItemsController extends AsyncNotifier<List<Video>> {
  PlaylistItemsController(this.playlistId);

  final String playlistId;

  @override
  Future<List<Video>> build() {
    return ref.read(playlistRepositoryProvider).fetchItems(playlistId);
  }

  /// Déplace un clip. L'ordre bascule tout de suite à l'écran, puis est
  /// renvoyé au serveur ; en cas d'échec on revient à l'ordre précédent.
  Future<String?> move(int oldIndex, int newIndex) async {
    final current = state.asData?.value;
    if (current == null) return null;

    // [newIndex] est déjà l'index de destination final : l'appelant utilise
    // `onReorderItem`, qui corrige lui-même le décalage dû au retrait de
    // l'élément (contrairement à l'ancien `onReorder`).
    final target = newIndex;
    if (target == oldIndex) return null;

    final reordered = [...current];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(target, moved);
    state = AsyncData(reordered);

    try {
      await ref
          .read(playlistRepositoryProvider)
          .reorder(
            playlistId: playlistId,
            videoIds: reordered.map((v) => v.id).toList(),
          );
      return null;
    } catch (error) {
      logError('réordonnancement impossible', error);
      state = AsyncData(current);
      return 'Le nouvel ordre n\'a pas pu être enregistré.';
    }
  }

  Future<String?> remove(String videoId) async {
    final current = state.asData?.value;
    if (current == null) return null;

    state = AsyncData(current.where((v) => v.id != videoId).toList());
    try {
      await ref
          .read(playlistRepositoryProvider)
          .removeVideo(playlistId: playlistId, videoId: videoId);
      ref.invalidate(myPlaylistsProvider);
      ref.invalidate(playlistByIdProvider(playlistId));
      return null;
    } catch (error) {
      logError('retrait de la playlist impossible', error);
      state = AsyncData(current);
      return 'Le clip n\'a pas pu être retiré.';
    }
  }
}

final playlistItemsControllerProvider =
    AsyncNotifierProvider.family<PlaylistItemsController, List<Video>, String>(
      PlaylistItemsController.new,
    );

/// Création, renommage et suppression de playlists.
class PlaylistController extends Notifier<bool> {
  /// L'état est simplement « une opération est en cours ».
  @override
  bool build() => false;

  /// Renvoie `null` en cas de succès, sinon le message d'erreur.
  Future<String?> create({
    required String title,
    String? description,
    bool isPublic = false,
  }) => _run(
    () => ref
        .read(playlistRepositoryProvider)
        .create(title: title, description: description, isPublic: isPublic),
  );

  Future<String?> rename({required String playlistId, required String title}) =>
      _run(
        () => ref
            .read(playlistRepositoryProvider)
            .update(playlistId: playlistId, title: title),
      );

  Future<String?> setVisibility({
    required String playlistId,
    required bool isPublic,
  }) => _run(
    () => ref
        .read(playlistRepositoryProvider)
        .update(playlistId: playlistId, isPublic: isPublic),
  );

  Future<String?> delete(String playlistId) =>
      _run(() => ref.read(playlistRepositoryProvider).delete(playlistId));

  Future<String?> addVideo({
    required String playlistId,
    required String videoId,
  }) => _run(
    () => ref
        .read(playlistRepositoryProvider)
        .addVideo(playlistId: playlistId, videoId: videoId),
    invalidateItemsOf: playlistId,
  );

  Future<String?> _run(
    Future<void> Function() action, {
    String? invalidateItemsOf,
  }) async {
    if (state) return null;
    state = true;
    try {
      await action();
      ref.invalidate(myPlaylistsProvider);
      if (invalidateItemsOf != null) {
        ref.invalidate(playlistItemsControllerProvider(invalidateItemsOf));
        ref.invalidate(playlistByIdProvider(invalidateItemsOf));
      }
      return null;
    } on PlaylistException catch (e) {
      return e.message;
    } catch (error) {
      logError('opération playlist impossible', error);
      return 'L\'opération a échoué. Réessaie.';
    } finally {
      state = false;
    }
  }
}

final playlistControllerProvider = NotifierProvider<PlaylistController, bool>(
  PlaylistController.new,
);
