import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/core/theme/theme_mode_provider.dart';
import 'package:vibeo/features/library/domain/playlist.dart';
import 'package:vibeo/features/library/presentation/playlist_screen.dart';
import 'package:vibeo/features/library/presentation/providers/library_providers.dart';
import 'package:vibeo/features/video/presentation/providers/video_providers.dart';

import '../../../helpers/fake_playlist_repository.dart';
import '../../../helpers/fake_video_repository.dart';

void main() {
  setUpAll(() {
    // Évite tout accès réseau aux polices pendant les tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final playlist = Playlist(
    id: 'playlist-1',
    ownerId: 'user-1',
    title: 'Nuit & basse',
    description: 'Mes sons préférés pour les longs trajets.',
    itemCount: 2,
    createdAt: DateTime(2026, 7, 1),
  );

  Future<ProviderContainer> pumpPlaylist(
    WidgetTester tester,
    ThemeData theme, {
    required FakePlaylistRepository playlistRepo,
    String playlistId = 'playlist-1',
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        videoRepositoryProvider.overrideWithValue(FakeVideoRepository()),
        playlistRepositoryProvider.overrideWithValue(playlistRepo),
      ],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme,
          home: PlaylistScreen(playlistId: playlistId),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';

    testWidgets(
      'PlaylistScreen affiche l\'en-tête et les clips (thème $name)',
      (tester) async {
        final repo = FakePlaylistRepository(
          playlists: [playlist],
          items: {
            'playlist-1': [
              buildTestVideo(id: 'video-1', title: 'Premier clip'),
              buildTestVideo(id: 'video-2', title: 'Deuxième clip'),
            ],
          },
        );
        await pumpPlaylist(
          tester,
          isDark ? AppTheme.dark : AppTheme.light,
          playlistRepo: repo,
        );
        await tester.pumpAndSettle();

        expect(find.text('Nuit & basse'), findsWidgets);
        expect(find.text('Premier clip'), findsOneWidget);
        expect(find.text('Deuxième clip'), findsOneWidget);
        expect(find.text('2 clips'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('PlaylistScreen affiche un état vide sans clip', (tester) async {
    final repo = FakePlaylistRepository(playlists: [playlist]);
    await pumpPlaylist(tester, AppTheme.dark, playlistRepo: repo);
    await tester.pumpAndSettle();

    expect(find.text('Cette playlist est vide'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PlaylistScreen affiche « introuvable » pour un id inconnu', (
    tester,
  ) async {
    final repo = FakePlaylistRepository();
    await pumpPlaylist(
      tester,
      AppTheme.light,
      playlistRepo: repo,
      playlistId: 'inconnu',
    );
    await tester.pumpAndSettle();

    expect(find.text('Playlist introuvable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PlaylistScreen affiche une erreur avec bouton Réessayer', (
    tester,
  ) async {
    final repo = FakePlaylistRepository(
      playlists: [playlist],
      throwOnFetch: true,
    );
    await pumpPlaylist(tester, AppTheme.light, playlistRepo: repo);
    await tester.pumpAndSettle();

    expect(find.text('Impossible de charger cette playlist.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PlaylistScreen se rend sans overflow sur petite largeur', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = FakePlaylistRepository(
      playlists: [playlist],
      items: {
        'playlist-1': [
          buildTestVideo(
            id: 'video-1',
            title: 'Un titre de clip volontairement très long ' * 2,
          ),
        ],
      },
    );
    await pumpPlaylist(tester, AppTheme.light, playlistRepo: repo);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
