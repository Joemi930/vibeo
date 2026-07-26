import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibeo/features/library/domain/playlist.dart';
import 'package:vibeo/features/library/presentation/providers/library_providers.dart';
import 'package:vibeo/features/upload/data/thumbnail_picker.dart';

import '../../../../helpers/fake_playlist_repository.dart';
import '../../../../helpers/fake_video_repository.dart';

void main() {
  const playlistId = 'playlist-1';

  final v1 = buildTestVideo(id: 'video-1', title: 'Premier');
  final v2 = buildTestVideo(id: 'video-2', title: 'Deuxième');
  final v3 = buildTestVideo(id: 'video-3', title: 'Troisième');

  ProviderContainer makeContainer(FakePlaylistRepository repo) {
    return ProviderContainer(
      overrides: [playlistRepositoryProvider.overrideWithValue(repo)],
      retry: (retryCount, error) => null,
    );
  }

  group('PlaylistItemsController.move', () {
    test(
      'newIndex est déjà la destination finale (API onReorderItem) : '
      'déplacer le premier élément en position 2 donne [v2, v3, v1]',
      () async {
        final repo = FakePlaylistRepository(
          items: {
            playlistId: [v1, v2, v3],
          },
        );
        final container = makeContainer(repo);
        addTearDown(container.dispose);
        await container.read(
          playlistItemsControllerProvider(playlistId).future,
        );

        final error = await container
            .read(playlistItemsControllerProvider(playlistId).notifier)
            .move(0, 2);

        expect(error, isNull);
        final state = container
            .read(playlistItemsControllerProvider(playlistId))
            .asData!
            .value;
        expect(state.map((v) => v.id), ['video-2', 'video-3', 'video-1']);
      },
    );

    test('déplacer le dernier élément en tête donne [v3, v1, v2]', () async {
      final repo = FakePlaylistRepository(
        items: {
          playlistId: [v1, v2, v3],
        },
      );
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(playlistItemsControllerProvider(playlistId).future);

      final error = await container
          .read(playlistItemsControllerProvider(playlistId).notifier)
          .move(2, 0);

      expect(error, isNull);
      final state = container
          .read(playlistItemsControllerProvider(playlistId))
          .asData!
          .value;
      expect(state.map((v) => v.id), ['video-3', 'video-1', 'video-2']);
    });

    test(
      'un déplacement vers le même index est un no-op (aucun appel serveur)',
      () async {
        final repo = FakePlaylistRepository(
          items: {
            playlistId: [v1, v2, v3],
          },
        );
        final container = makeContainer(repo);
        addTearDown(container.dispose);
        await container.read(
          playlistItemsControllerProvider(playlistId).future,
        );

        final error = await container
            .read(playlistItemsControllerProvider(playlistId).notifier)
            .move(1, 1);

        expect(error, isNull);
        expect(repo.calls.any((c) => c.startsWith('reorder:')), isFalse);
        final state = container
            .read(playlistItemsControllerProvider(playlistId))
            .asData!
            .value;
        expect(state.map((v) => v.id), ['video-1', 'video-2', 'video-3']);
      },
    );

    test(
      'un échec serveur restaure l\'ordre précédent et renvoie un message',
      () async {
        final repo = FakePlaylistRepository(
          items: {
            playlistId: [v1, v2, v3],
          },
          throwOnWrite: true,
        );
        final container = makeContainer(repo);
        addTearDown(container.dispose);
        await container.read(
          playlistItemsControllerProvider(playlistId).future,
        );

        final error = await container
            .read(playlistItemsControllerProvider(playlistId).notifier)
            .move(0, 2);

        expect(error, 'Le nouvel ordre n\'a pas pu être enregistré.');
        final state = container
            .read(playlistItemsControllerProvider(playlistId))
            .asData!
            .value;
        // L'ordre d'origine est restauré, pas l'ordre optimiste erroné.
        expect(state.map((v) => v.id), ['video-1', 'video-2', 'video-3']);
      },
    );

    test(
      'l\'ordre envoyé au serveur reflète bien l\'ordre optimiste',
      () async {
        final repo = FakePlaylistRepository(
          items: {
            playlistId: [v1, v2, v3],
          },
        );
        final container = makeContainer(repo);
        addTearDown(container.dispose);
        await container.read(
          playlistItemsControllerProvider(playlistId).future,
        );

        await container
            .read(playlistItemsControllerProvider(playlistId).notifier)
            .move(0, 2);

        expect(
          repo.calls,
          contains('reorder:$playlistId:video-2,video-3,video-1'),
        );
      },
    );
  });

  group('PlaylistItemsController.remove', () {
    test(
      'retire le clip de façon optimiste puis invalide les listes',
      () async {
        final repo = FakePlaylistRepository(
          items: {
            playlistId: [v1, v2],
          },
        );
        final container = makeContainer(repo);
        addTearDown(container.dispose);
        await container.read(
          playlistItemsControllerProvider(playlistId).future,
        );

        final error = await container
            .read(playlistItemsControllerProvider(playlistId).notifier)
            .remove('video-1');

        expect(error, isNull);
        final state = container
            .read(playlistItemsControllerProvider(playlistId))
            .asData!
            .value;
        expect(state.map((v) => v.id), ['video-2']);
      },
    );

    test('un échec serveur restaure le clip retiré', () async {
      final repo = FakePlaylistRepository(
        items: {
          playlistId: [v1, v2],
        },
        throwOnWrite: true,
      );
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(playlistItemsControllerProvider(playlistId).future);

      final error = await container
          .read(playlistItemsControllerProvider(playlistId).notifier)
          .remove('video-1');

      expect(error, 'Le clip n\'a pas pu être retiré.');
      final state = container
          .read(playlistItemsControllerProvider(playlistId))
          .asData!
          .value;
      expect(state.map((v) => v.id), ['video-1', 'video-2']);
    });
  });

  group('PlaylistController.createDetailed avec couverture', () {
    final cover = PickedThumbnail(
      bytes: Uint8List.fromList([1, 2, 3]),
      fileExtension: 'jpg',
      contentType: 'image/jpeg',
    );

    test('téléverse la couverture puis met à jour cover_path', () async {
      final repo = FakePlaylistRepository();
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final outcome = await container
          .read(playlistControllerProvider.notifier)
          .createDetailed(title: 'Nouvelle liste', cover: cover);

      expect(outcome.error, isNull);
      expect(outcome.playlist?.coverPath, isNotNull);
      expect(repo.calls, contains('uploadCover:${outcome.playlist!.id}'));
      expect(repo.calls, contains('update:${outcome.playlist!.id}'));
    });

    test('un échec de téléversement ne laisse pas une playlist fantôme : elle '
        'est renvoyée quand même, avec un message dédié', () async {
      final repo = FakePlaylistRepository(throwOnCoverUpload: true);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final outcome = await container
          .read(playlistControllerProvider.notifier)
          .createDetailed(title: 'Nouvelle liste', cover: cover);

      expect(outcome.playlist, isNotNull);
      expect(outcome.playlist!.coverPath, isNull);
      expect(
        outcome.error,
        'Playlist créée, mais l\'image n\'a pas pu être ajoutée.',
      );
      // La playlist existe bel et bien côté dépôt.
      expect(repo.playlists.map((p) => p.id), contains(outcome.playlist!.id));
    });

    test('sans couverture, aucun appel de téléversement n\'est fait', () async {
      final repo = FakePlaylistRepository();
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(playlistControllerProvider.notifier)
          .createDetailed(title: 'Sans image');

      expect(repo.calls.any((c) => c.startsWith('uploadCover:')), isFalse);
    });
  });

  group('PlaylistController.edit', () {
    final existing = Playlist(
      id: 'playlist-1',
      ownerId: 'user-1',
      title: 'Titre initial',
      createdAt: DateTime(2026, 7, 25),
      coverPath: 'user-1/playlist-1.jpg',
    );

    test('remplace la couverture et supprime l\'ancien fichier', () async {
      final repo = FakePlaylistRepository(playlists: [existing]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final newCover = PickedThumbnail(
        bytes: Uint8List.fromList([4, 5, 6]),
        fileExtension: 'png',
        contentType: 'image/png',
      );

      final error = await container
          .read(playlistControllerProvider.notifier)
          .edit(
            playlistId: existing.id,
            ownerId: existing.ownerId,
            title: 'Titre modifié',
            newCover: newCover,
            previousCoverPath: existing.coverPath,
          );

      expect(error, isNull);
      expect(repo.playlists.single.title, 'Titre modifié');
      expect(repo.playlists.single.coverPath, isNot(existing.coverPath));
      expect(repo.calls, contains('removeCoverFile:${existing.coverPath}'));
    });

    test('removeCover efface cover_path et supprime le fichier', () async {
      final repo = FakePlaylistRepository(playlists: [existing]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final error = await container
          .read(playlistControllerProvider.notifier)
          .edit(
            playlistId: existing.id,
            ownerId: existing.ownerId,
            title: existing.title,
            removeCover: true,
            previousCoverPath: existing.coverPath,
          );

      expect(error, isNull);
      expect(repo.playlists.single.coverPath, isNull);
      expect(repo.calls, contains('removeCoverFile:${existing.coverPath}'));
    });

    test(
      'sans changement de couverture, aucun fichier n\'est touché',
      () async {
        final repo = FakePlaylistRepository(playlists: [existing]);
        final container = makeContainer(repo);
        addTearDown(container.dispose);

        await container
            .read(playlistControllerProvider.notifier)
            .edit(
              playlistId: existing.id,
              ownerId: existing.ownerId,
              title: 'Autre titre',
              previousCoverPath: existing.coverPath,
            );

        expect(
          repo.calls.any((c) => c.startsWith('removeCoverFile:')),
          isFalse,
        );
        expect(repo.calls.any((c) => c.startsWith('uploadCover:')), isFalse);
        expect(repo.playlists.single.coverPath, existing.coverPath);
      },
    );
  });
}
