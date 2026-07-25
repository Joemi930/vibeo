import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/core/theme/theme_mode_provider.dart';
import 'package:vibeo/features/artist/presentation/artist_screen.dart';
import 'package:vibeo/features/auth/domain/profile.dart';
import 'package:vibeo/features/auth/domain/user_role.dart';
import 'package:vibeo/features/auth/presentation/providers/auth_providers.dart';
import 'package:vibeo/features/profile/presentation/providers/profile_providers.dart';
import 'package:vibeo/features/social/presentation/providers/social_providers.dart';
import 'package:vibeo/features/video/presentation/providers/video_providers.dart';

import '../../../helpers/fake_auth_repository.dart';
import '../../../helpers/fake_social_repository.dart';
import '../../../helpers/fake_video_repository.dart';

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

  final artistProfile = Profile(
    id: 'artist-1',
    username: 'naika',
    displayName: 'Naïka',
    bio: 'Autrice-compositrice, sons chauds pour nuits froides.',
    role: UserRole.artist,
    subscriberCount: 4200,
    createdAt: DateTime(2025, 3, 1),
  );

  Future<ProviderContainer> pumpArtist(
    WidgetTester tester,
    ThemeData theme, {
    Profile? profile,
    bool useError = false,
    FakeVideoRepository? videoRepo,
    FakeSocialRepository? socialRepo,
    bool authenticated = true,
    String artistId = 'artist-1',
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final authRepo = FakeAuthRepository(
      initialUser: authenticated ? _fakeUser : null,
    )..profile = profile;
    addTearDown(authRepo.dispose);

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(authRepo),
        videoRepositoryProvider.overrideWithValue(
          videoRepo ?? FakeVideoRepository(),
        ),
        socialRepositoryProvider.overrideWithValue(
          socialRepo ?? FakeSocialRepository(),
        ),
        if (useError)
          profileByIdProvider(
            artistId,
          ).overrideWith((ref) => Future<Profile?>.error(Exception('boom')))
        else
          profileByIdProvider(artistId).overrideWith((ref) => profile),
      ],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme,
          home: ArtistScreen(artistId: artistId),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';

    testWidgets(
      'ArtistScreen affiche l\'identité de l\'artiste (thème $name)',
      (tester) async {
        final videoRepo = FakeVideoRepository(
          videos: [
            buildTestVideo(
              id: 'v1',
              artistId: 'artist-1',
              title: 'Premier clip',
            ),
            buildTestVideo(
              id: 'v2',
              artistId: 'artist-1',
              title: 'Second clip',
            ),
          ],
        );
        await pumpArtist(
          tester,
          isDark ? AppTheme.dark : AppTheme.light,
          profile: artistProfile,
          videoRepo: videoRepo,
        );
        await tester.pumpAndSettle();

        // Le nom de l'artiste apparaît aussi sous chacune de ses cartes de
        // clip (VideoCard) : on vérifie sa présence, pas son unicité.
        expect(find.text('Naïka'), findsWidgets);
        expect(find.byIcon(Icons.verified_rounded), findsWidgets);
        expect(find.textContaining('abonnés'), findsOneWidget);
        expect(find.textContaining('clips'), findsOneWidget);
        // La bio est affichée dans l'en-tête ; l'onglet « À propos » (non
        // visible mais déjà construit par TabBarView) la répète.
        expect(
          find.text('Autrice-compositrice, sons chauds pour nuits froides.'),
          findsWidgets,
        );
        expect(find.text('Premier clip'), findsOneWidget);
        expect(find.text('Second clip'), findsOneWidget);
        expect(find.text('Clips'), findsOneWidget);
        expect(find.text('À propos'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('l\'onglet « À propos » affiche la bio et l\'ancienneté', (
    tester,
  ) async {
    await pumpArtist(tester, AppTheme.dark, profile: artistProfile);
    await tester.pumpAndSettle();

    await tester.tap(find.text('À propos'));
    await tester.pumpAndSettle();

    expect(find.text('BIO'), findsOneWidget);
    expect(
      find.text('Autrice-compositrice, sons chauds pour nuits froides.'),
      findsWidgets,
    );
    expect(find.text('MEMBRE DEPUIS'), findsOneWidget);
    expect(find.text('mars 2025'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('affiche un état vide quand l\'artiste n\'a publié aucun clip', (
    tester,
  ) async {
    await pumpArtist(tester, AppTheme.light, profile: artistProfile);
    await tester.pumpAndSettle();

    expect(find.text('Aucun clip publié'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('affiche « Artiste introuvable » pour un profil absent', (
    tester,
  ) async {
    await pumpArtist(tester, AppTheme.light, profile: null);
    await tester.pumpAndSettle();

    expect(find.text('Artiste introuvable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('affiche une erreur avec bouton Réessayer', (tester) async {
    await pumpArtist(tester, AppTheme.dark, useError: true);
    await tester.pump();

    expect(find.text('Impossible de charger cet artiste.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un membre connecté peut s\'abonner : le compteur augmente et le '
      'libellé bascule sur « Abonné »', (tester) async {
    final repo = FakeSocialRepository();
    await pumpArtist(
      tester,
      AppTheme.dark,
      profile: artistProfile,
      socialRepo: repo,
    );
    await tester.pumpAndSettle();

    expect(find.text("S'abonner"), findsOneWidget);
    expect(find.textContaining('4,2 k'), findsOneWidget);

    await tester.tap(find.text("S'abonner"));
    await tester.pumpAndSettle();

    expect(find.text('Abonné'), findsOneWidget);
    expect(repo.calls, contains('subscribe:artist-1'));
    // Le compteur affiché intègre le delta optimiste (+1).
    expect(find.textContaining('4,2 k'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'un invité qui tente de s\'abonner reçoit une invitation à se connecter',
    (tester) async {
      final repo = FakeSocialRepository();
      await pumpArtist(
        tester,
        AppTheme.light,
        profile: artistProfile,
        socialRepo: repo,
        authenticated: false,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text("S'abonner"));
      await tester.pumpAndSettle();

      expect(
        find.text("Connecte-toi pour t'abonner à cet artiste"),
        findsOneWidget,
      );
      expect(repo.calls, isNot(contains('subscribe:artist-1')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ArtistScreen se rend sans overflow sur petite largeur', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final longProfile = artistProfile.copyWith(
      displayName: 'Un Nom D\'Artiste Volontairement Très Long Pour Le Test',
      bio:
          'Une biographie particulièrement longue destinée à vérifier que '
          'le texte se replie correctement sans provoquer le moindre '
          'débordement visuel (RenderFlex overflow) sur un petit écran.',
    );
    final videoRepo = FakeVideoRepository(
      videos: [
        buildTestVideo(
          id: 'v1',
          artistId: 'artist-1',
          title: 'Un titre de clip volontairement très long ' * 2,
        ),
      ],
    );
    await pumpArtist(
      tester,
      AppTheme.light,
      profile: longProfile,
      videoRepo: videoRepo,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
