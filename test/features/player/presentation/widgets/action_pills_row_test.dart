import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/features/auth/presentation/providers/auth_providers.dart';
import 'package:vibeo/features/library/domain/playlist.dart';
import 'package:vibeo/features/library/presentation/providers/library_providers.dart';
import 'package:vibeo/features/player/presentation/widgets/action_pills_row.dart';
import 'package:vibeo/features/social/presentation/providers/social_providers.dart';

import '../../../../helpers/fake_auth_repository.dart';
import '../../../../helpers/fake_playlist_repository.dart';
import '../../../../helpers/fake_social_repository.dart';
import '../../../../helpers/fake_video_repository.dart';

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

  Future<ProviderContainer> pumpPills(
    WidgetTester tester, {
    FakePlaylistRepository? playlistRepo,
    bool authenticated = true,
  }) async {
    final authRepo = FakeAuthRepository(
      initialUser: authenticated ? _fakeUser : null,
    );
    addTearDown(authRepo.dispose);
    final video = buildTestVideo(id: 'video-1', title: 'Mon clip');

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        socialRepositoryProvider.overrideWithValue(FakeSocialRepository()),
        playlistRepositoryProvider.overrideWithValue(
          playlistRepo ?? FakePlaylistRepository(),
        ),
      ],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ActionPillsRow(video: video, onComment: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'un invité qui touche la pilule « Playlist » reçoit l\'invitation à se '
    'connecter, sans appel réseau',
    (tester) async {
      final playlistRepo = FakePlaylistRepository();
      await pumpPills(tester, playlistRepo: playlistRepo, authenticated: false);

      await tester.tap(find.text('Playlist'));
      await tester.pumpAndSettle();

      expect(
        find.text('Connecte-toi pour ajouter ce clip à une playlist'),
        findsOneWidget,
      );
      expect(playlistRepo.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'un utilisateur connecté qui touche la pilule « Playlist » voit ses '
    'playlists',
    (tester) async {
      final playlistRepo = FakePlaylistRepository(
        playlists: [
          Playlist(
            id: 'playlist-1',
            ownerId: 'user-1',
            title: 'Mes favoris',
            createdAt: DateTime(2026, 7, 1),
          ),
        ],
      );
      await pumpPills(tester, playlistRepo: playlistRepo);

      await tester.tap(find.text('Playlist'));
      await tester.pumpAndSettle();

      expect(find.text('Ajouter à une playlist'), findsOneWidget);
      expect(find.text('Mes favoris'), findsOneWidget);
      expect(playlistRepo.calls, contains('fetchMine'));
      expect(tester.takeException(), isNull);
    },
  );
}
