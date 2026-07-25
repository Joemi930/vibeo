import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibeo/features/library/presentation/providers/library_providers.dart';

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
}
