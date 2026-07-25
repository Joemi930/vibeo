import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/core/theme/theme_mode_provider.dart';
import 'package:vibeo/features/auth/domain/user_role.dart';
import 'package:vibeo/features/search/presentation/providers/search_providers.dart';
import 'package:vibeo/features/search/presentation/search_screen.dart';
import 'package:vibeo/features/video/domain/artist_summary.dart';
import 'package:vibeo/features/video/domain/genre.dart';
import 'package:vibeo/features/video/presentation/providers/video_providers.dart';

import '../../../helpers/fake_search_repository.dart';
import '../../../helpers/fake_video_repository.dart';

void main() {
  setUpAll(() {
    // Évite tout accès réseau aux polices pendant les tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<ProviderContainer> pumpSearch(
    WidgetTester tester,
    ThemeData theme, {
    FakeSearchRepository? searchRepo,
    List<Genre> genres = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        videoRepositoryProvider.overrideWithValue(
          FakeVideoRepository(genres: genres),
        ),
        searchRepositoryProvider.overrideWithValue(
          searchRepo ?? FakeSearchRepository(),
        ),
      ],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: theme, home: const SearchScreen()),
      ),
    );
    await tester.pump();
    return container;
  }

  /// Saisit une requête puis la valide immédiatement (au lieu d'attendre le
  /// délai d'attente de 300 ms du contrôleur), pour des tests déterministes.
  Future<void> searchFor(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';

    testWidgets(
      'SearchScreen affiche l\'état initial (aucune recherche) en thème '
      '$name',
      (tester) async {
        await pumpSearch(
          tester,
          isDark ? AppTheme.dark : AppTheme.light,
          genres: const [Genre(id: 1, name: 'Afrobeat', slug: 'afrobeat')],
        );
        await tester.pumpAndSettle();

        expect(find.text('Recherche'), findsOneWidget);
        expect(find.text('Clips'), findsOneWidget);
        expect(find.text('Artistes'), findsOneWidget);
        expect(find.text('Tous'), findsOneWidget);
        expect(find.text('Afrobeat'), findsOneWidget);
        expect(find.text('Trouve un clip ou un artiste'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('SearchScreen affiche les clips correspondant à la requête', (
    tester,
  ) async {
    final repo = FakeSearchRepository(
      videos: [buildTestVideo(title: 'Ciel ouvert — Session live')],
    );
    await pumpSearch(tester, AppTheme.dark, searchRepo: repo);

    await searchFor(tester, 'ciel');

    expect(find.text('Ciel ouvert — Session live'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'SearchScreen affiche « aucun résultat » puis efface la recherche',
    (tester) async {
      final repo = FakeSearchRepository();
      await pumpSearch(tester, AppTheme.light, searchRepo: repo);

      await searchFor(tester, 'zxqwrt');

      expect(find.text('Aucun résultat pour « zxqwrt »'), findsOneWidget);
      expect(find.text('Effacer la recherche'), findsOneWidget);

      await tester.tap(find.text('Effacer la recherche'));
      await tester.pumpAndSettle();

      expect(find.text('Trouve un clip ou un artiste'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('SearchScreen masque le filtre de genre sur l\'onglet Artistes', (
    tester,
  ) async {
    await pumpSearch(
      tester,
      AppTheme.dark,
      genres: const [Genre(id: 1, name: 'Afrobeat', slug: 'afrobeat')],
    );
    await tester.pumpAndSettle();

    expect(find.text('Tous'), findsOneWidget);

    await tester.tap(find.text('Artistes'));
    await tester.pumpAndSettle();

    expect(find.text('Tous'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SearchScreen affiche les artistes correspondant à la requête', (
    tester,
  ) async {
    final repo = FakeSearchRepository(
      artists: [
        const ArtistSummary(
          id: 'artist-1',
          username: 'naika',
          displayName: 'Naïka',
          role: UserRole.artist,
          subscriberCount: 412000,
        ),
      ],
    );
    await pumpSearch(tester, AppTheme.light, searchRepo: repo);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Artistes'));
    await tester.pumpAndSettle();

    await searchFor(tester, 'naïka');

    expect(find.text('Naïka'), findsOneWidget);
    expect(find.textContaining('abonnés'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SearchScreen affiche une erreur avec bouton Réessayer', (
    tester,
  ) async {
    final repo = FakeSearchRepository(throwOnSearch: true);
    await pumpSearch(tester, AppTheme.dark, searchRepo: repo);

    await searchFor(tester, 'naika');

    expect(find.text('La recherche a échoué.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SearchScreen se rend sans overflow sur petite largeur', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = FakeSearchRepository(
      videos: [
        buildTestVideo(title: 'Un titre de clip volontairement très long ' * 2),
      ],
    );
    await pumpSearch(
      tester,
      AppTheme.light,
      searchRepo: repo,
      genres: const [
        Genre(id: 1, name: 'Afrobeat', slug: 'afrobeat'),
        Genre(id: 2, name: 'Pop', slug: 'pop'),
        Genre(id: 3, name: 'RnB', slug: 'rnb'),
      ],
    );

    await searchFor(tester, 'titre');

    expect(tester.takeException(), isNull);
  });
}
