import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/core/theme/theme_mode_provider.dart';
import 'package:vibeo/features/auth/presentation/providers/auth_providers.dart';
import 'package:vibeo/features/library/domain/playlist.dart';
import 'package:vibeo/features/library/presentation/library_screen.dart';
import 'package:vibeo/features/library/presentation/providers/library_providers.dart';
import 'package:vibeo/features/social/presentation/providers/social_providers.dart';
import 'package:vibeo/features/video/presentation/providers/video_providers.dart';

import '../../../helpers/fake_auth_repository.dart';
import '../../../helpers/fake_playlist_repository.dart';
import '../../../helpers/fake_social_repository.dart';
import '../../../helpers/fake_video_repository.dart';

/// Utilisateur factice pour simuler un compte connecté.
final _fakeUser = User(
  id: 'user-1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime(2026, 1, 1).toIso8601String(),
);

void main() {
  setUpAll(() {
    // Évite tout accès réseau aux polices pendant les tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<ProviderContainer> pumpLibrary(
    WidgetTester tester,
    ThemeData theme, {
    bool authenticated = true,
    FakePlaylistRepository? playlistRepo,
    FakeSocialRepository? socialRepo,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final authRepo = FakeAuthRepository(
      initialUser: authenticated ? _fakeUser : null,
    );
    addTearDown(authRepo.dispose);

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(authRepo),
        videoRepositoryProvider.overrideWithValue(FakeVideoRepository()),
        playlistRepositoryProvider.overrideWithValue(
          playlistRepo ?? FakePlaylistRepository(),
        ),
        socialRepositoryProvider.overrideWithValue(
          socialRepo ?? FakeSocialRepository(),
        ),
      ],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: theme, home: const LibraryScreen()),
      ),
    );
    await tester.pump();
    return container;
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';

    testWidgets(
      'LibraryScreen invite un invité à se connecter en thème $name',
      (tester) async {
        await pumpLibrary(
          tester,
          isDark ? AppTheme.dark : AppTheme.light,
          authenticated: false,
        );
        await tester.pump();

        expect(find.text('Bibliothèque'), findsOneWidget);
        expect(find.text('Bibliothèque réservée aux membres'), findsOneWidget);
        expect(find.text('Playlists'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'LibraryScreen affiche les trois onglets pour un membre connecté '
      '(thème $name)',
      (tester) async {
        await pumpLibrary(tester, isDark ? AppTheme.dark : AppTheme.light);
        await tester.pumpAndSettle();

        expect(find.text('Playlists'), findsOneWidget);
        expect(find.text('Abonnements'), findsOneWidget);
        expect(find.text('Historique'), findsOneWidget);
        // Onglet par défaut : Playlists, sans playlist encore créée.
        expect(find.text("Aucune playlist pour l'instant"), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('LibraryScreen liste les playlists avec leurs métadonnées', (
    tester,
  ) async {
    final repo = FakePlaylistRepository(
      playlists: [
        Playlist(
          id: 'playlist-1',
          ownerId: 'user-1',
          title: 'Nuit & basse',
          isPublic: true,
          itemCount: 24,
          createdAt: DateTime(2026, 7, 1),
        ),
        Playlist(
          id: 'playlist-2',
          ownerId: 'user-1',
          title: 'Titres likés',
          itemCount: 87,
          createdAt: DateTime(2026, 7, 2),
        ),
      ],
    );
    await pumpLibrary(tester, AppTheme.dark, playlistRepo: repo);
    await tester.pumpAndSettle();

    expect(find.text('Nuit & basse'), findsOneWidget);
    expect(find.text('24 clips'), findsOneWidget);
    expect(find.text('Titres likés'), findsOneWidget);
    expect(find.text('87 clips'), findsOneWidget);
    // La playlist privée porte un cadenas, pas la publique.
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LibraryScreen affiche une erreur avec bouton Réessayer sur les '
      'playlists', (tester) async {
    final repo = FakePlaylistRepository(throwOnFetch: true);
    await pumpLibrary(tester, AppTheme.light, playlistRepo: repo);
    await tester.pumpAndSettle();

    expect(find.text('Impossible de charger tes playlists.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LibraryScreen se rend sans overflow sur petite largeur', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = FakePlaylistRepository(
      playlists: [
        Playlist(
          id: 'playlist-1',
          ownerId: 'user-1',
          title: 'Un titre de playlist volontairement très long ' * 2,
          itemCount: 24,
          createdAt: DateTime(2026, 7, 1),
        ),
      ],
    );
    await pumpLibrary(tester, AppTheme.light, playlistRepo: repo);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
