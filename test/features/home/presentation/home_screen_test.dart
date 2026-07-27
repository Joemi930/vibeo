import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/core/theme/theme_mode_provider.dart';
import 'package:vibeo/features/auth/presentation/providers/auth_providers.dart';
import 'package:vibeo/features/home/presentation/home_screen.dart';
import 'package:vibeo/features/home/presentation/providers/discovery_providers.dart';
import 'package:vibeo/features/video/domain/genre.dart';
import 'package:vibeo/features/video/presentation/providers/video_providers.dart';

import '../../../helpers/fake_auth_repository.dart';
import '../../../helpers/fake_video_repository.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<ProviderContainer> pumpHome(
    WidgetTester tester,
    ThemeData theme, {
    FakeVideoRepository? videoRepo,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final authRepo = FakeAuthRepository();
    addTearDown(authRepo.dispose);

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(authRepo),
        videoRepositoryProvider.overrideWithValue(
          videoRepo ?? FakeVideoRepository(),
        ),
        trendingVideosProvider.overrideWith((ref) => const []),
        recommendedVideosProvider.overrideWith((ref) => const []),
      ],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: theme, home: const HomeScreen()),
      ),
    );
    await tester.pump();
    return container;
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';

    testWidgets('HomeScreen se rend en thème $name sans overflow', (
      tester,
    ) async {
      await pumpHome(tester, isDark ? AppTheme.dark : AppTheme.light);
      await tester.pumpAndSettle();

      expect(find.text('Vibeo'), findsOneWidget);
      expect(find.text('Nouveautés'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('HomeScreen liste les clips publiés en thème $name', (
      tester,
    ) async {
      final repo = FakeVideoRepository(
        videos: [
          buildTestVideo(title: 'Clip de démonstration'),
          buildTestVideo(id: 'video-2', title: 'Deuxième clip'),
        ],
        genres: const [Genre(id: 1, name: 'Afrobeats', slug: 'afrobeats')],
      );
      await pumpHome(
        tester,
        isDark ? AppTheme.dark : AppTheme.light,
        videoRepo: repo,
      );
      await tester.pumpAndSettle();

      expect(find.text('Clip de démonstration'), findsOneWidget);
      expect(find.text('Deuxième clip'), findsOneWidget);
      expect(find.text('Tous'), findsOneWidget);
      expect(find.text('Afrobeats'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('HomeScreen affiche un état vide quand aucun clip n\'existe', (
    tester,
  ) async {
    await pumpHome(tester, AppTheme.dark);
    await tester.pumpAndSettle();

    expect(find.text('Aucun clip pour le moment'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HomeScreen affiche une erreur avec bouton Réessayer', (
    tester,
  ) async {
    final repo = FakeVideoRepository(throwOnFetch: true);
    await pumpHome(tester, AppTheme.light, videoRepo: repo);
    await tester.pumpAndSettle();

    expect(find.text('Impossible de charger les clips.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HomeScreen se rend sans overflow sur petite largeur', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = FakeVideoRepository(
      videos: [buildTestVideo(title: 'Un titre volontairement très long ' * 3)],
    );
    await pumpHome(tester, AppTheme.light, videoRepo: repo);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
