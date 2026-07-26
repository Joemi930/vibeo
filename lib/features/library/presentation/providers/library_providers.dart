import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/dev_log.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../upload/data/thumbnail_picker.dart';
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

/// URL signée d'une couverture de playlist (le bucket est privé).
final playlistCoverUrlProvider = FutureProvider.family<String?, String?>((
  ref,
  path,
) {
  return ref.watch(playlistRepositoryProvider).signedCoverUrl(path);
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
  }) async => (await createDetailed(
    title: title,
    description: description,
    isPublic: isPublic,
  )).error;

  /// Crée une playlist et renvoie **l'objet créé**, pour l'appelant qui doit
  /// enchaîner dessus (« Nouvelle playlist » puis ajout immédiat du clip).
  ///
  /// [create] jette cet objet et ne renvoie qu'un message d'erreur : retrouver
  /// ensuite la playlist par son titre viserait la mauvaise dès que deux
  /// playlists portent le même nom — ce que rien n'interdit.
  ///
  /// [cover], si fourni, est téléversé **après** la création de la ligne : son
  /// chemin de stockage dépend de l'identifiant de la playlist, généré par la
  /// base. Si ce second appel échoue, la playlist existe déjà et n'est pas
  /// « fantôme » : elle est renvoyée quand même, accompagnée d'un message
  /// distinct pour que l'appelant prévienne l'utilisateur au lieu de laisser
  /// croire que rien ne s'est passé.
  Future<({Playlist? playlist, String? error})> createDetailed({
    required String title,
    String? description,
    bool isPublic = false,
    PickedThumbnail? cover,
  }) async {
    if (state) return (playlist: null, error: null);
    state = true;
    try {
      final repo = ref.read(playlistRepositoryProvider);
      final created = await repo.create(
        title: title,
        description: description,
        isPublic: isPublic,
      );
      ref.invalidate(myPlaylistsProvider);

      if (cover == null) return (playlist: created, error: null);

      try {
        final path = await repo.uploadCover(
          userId: created.ownerId,
          playlistId: created.id,
          bytes: cover.bytes,
          fileExtension: cover.fileExtension,
          contentType: cover.contentType,
        );
        final updated = await repo.update(
          playlistId: created.id,
          coverPath: path,
        );
        ref.invalidate(myPlaylistsProvider);
        ref.invalidate(playlistByIdProvider(created.id));
        return (playlist: updated, error: null);
      } catch (error) {
        logError('ajout de couverture à la création impossible', error);
        return (
          playlist: created,
          error: 'Playlist créée, mais l\'image n\'a pas pu être ajoutée.',
        );
      }
    } on PlaylistException catch (e) {
      return (playlist: null, error: e.message);
    } catch (error) {
      logError('création de playlist impossible', error);
      return (playlist: null, error: 'L\'opération a échoué. Réessaie.');
    } finally {
      state = false;
    }
  }

  /// Modifie titre et/ou couverture d'une playlist existante.
  ///
  /// [newCover] remplace la couverture actuelle ; [removeCover] la retire.
  /// [ownerId] et [previousCoverPath] viennent de la playlist déjà chargée
  /// par l'appelant : aucun aller-retour réseau supplémentaire n'est
  /// nécessaire pour les connaître.
  Future<String?> edit({
    required String playlistId,
    required String ownerId,
    required String title,
    PickedThumbnail? newCover,
    bool removeCover = false,
    String? previousCoverPath,
  }) => _run(() async {
    final repo = ref.read(playlistRepositoryProvider);
    String? coverPath;
    if (!removeCover && newCover != null) {
      coverPath = await repo.uploadCover(
        userId: ownerId,
        playlistId: playlistId,
        bytes: newCover.bytes,
        fileExtension: newCover.fileExtension,
        contentType: newCover.contentType,
      );
    }

    await repo.update(
      playlistId: playlistId,
      title: title,
      coverPath: coverPath,
      clearCover: removeCover,
    );

    // Le fichier remplacé ou retiré ne sert plus à rien : le supprimer est un
    // effort raisonnable, non bloquant (voir `removeCoverFile`).
    if ((removeCover || coverPath != null) &&
        previousCoverPath != null &&
        previousCoverPath.isNotEmpty) {
      await repo.removeCoverFile(previousCoverPath);
    }
  }, invalidateItemsOf: playlistId);

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
