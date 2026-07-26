import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/features/library/domain/playlist.dart';
import 'package:vibeo/features/library/presentation/providers/library_providers.dart';
import 'package:vibeo/features/library/presentation/widgets/add_to_playlist_sheet.dart';

import '../../../../helpers/fake_playlist_repository.dart';
import '../../../../helpers/fake_video_repository.dart';

void main() {
  final video = buildTestVideo(id: 'video-1', title: 'Mon clip');

  Future<ProviderContainer> pumpSheet(
    WidgetTester tester,
    FakePlaylistRepository repo,
  ) async {
    final container = ProviderContainer(
      overrides: [playlistRepositoryProvider.overrideWithValue(repo)],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAddToPlaylistSheet(context, video),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('affiche les playlists avec leur état d\'appartenance', (
    tester,
  ) async {
    final repo = FakePlaylistRepository(
      playlists: [
        Playlist(
          id: 'playlist-1',
          ownerId: 'user-1',
          title: 'Mes favoris',
          createdAt: DateTime(2026, 7, 1),
        ),
        Playlist(
          id: 'playlist-2',
          ownerId: 'user-1',
          title: 'À écouter',
          createdAt: DateTime(2026, 7, 2),
        ),
      ],
      items: {
        'playlist-1': [video],
      },
    );
    await pumpSheet(tester, repo);

    expect(find.text('Mes favoris'), findsOneWidget);
    expect(find.text('À écouter'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ajoute le clip à une playlist qui ne le contient pas encore', (
    tester,
  ) async {
    final repo = FakePlaylistRepository(
      playlists: [
        Playlist(
          id: 'playlist-1',
          ownerId: 'user-1',
          title: 'Mes favoris',
          createdAt: DateTime(2026, 7, 1),
        ),
      ],
    );
    await pumpSheet(tester, repo);

    await tester.tap(find.text('Mes favoris'));
    await tester.pumpAndSettle();

    expect(repo.calls, contains('addVideo:playlist-1:video-1'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('retire le clip d\'une playlist qui le contient déjà', (
    tester,
  ) async {
    final repo = FakePlaylistRepository(
      playlists: [
        Playlist(
          id: 'playlist-1',
          ownerId: 'user-1',
          title: 'Mes favoris',
          createdAt: DateTime(2026, 7, 1),
        ),
      ],
      items: {
        'playlist-1': [video],
      },
    );
    await pumpSheet(tester, repo);

    await tester.tap(find.text('Mes favoris'));
    await tester.pumpAndSettle();

    expect(repo.calls, contains('removeVideo:playlist-1:video-1'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('crée une playlist à la volée puis y ajoute le clip', (
    tester,
  ) async {
    final repo = FakePlaylistRepository();
    await pumpSheet(tester, repo);

    expect(
      find.text('Tu n\'as encore aucune playlist. Crée-en une ci-dessous.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'Ma nouvelle playlist');
    await tester.tap(find.byTooltip('Créer la playlist et y ajouter ce clip'));
    await tester.pumpAndSettle();

    expect(repo.calls, contains('create:Ma nouvelle playlist'));
    expect(
      repo.calls.any(
        (c) => c.startsWith('addVideo:') && c.endsWith(':video-1'),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('affiche l\'erreur métier au lieu d\'ajouter le clip', (
    tester,
  ) async {
    final repo = FakePlaylistRepository(
      playlists: [
        Playlist(
          id: 'playlist-1',
          ownerId: 'user-1',
          title: 'Mes favoris',
          createdAt: DateTime(2026, 7, 1),
        ),
      ],
      throwOnWrite: true,
    );
    await pumpSheet(tester, repo);

    await tester.tap(find.text('Mes favoris'));
    await tester.pumpAndSettle();

    expect(find.text('Échec simulé.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
