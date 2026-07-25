import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeo/core/router/app_routes.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/core/theme/theme_mode_provider.dart';
import 'package:vibeo/features/auth/data/auth_repository.dart';
import 'package:vibeo/features/auth/presentation/auth_screen.dart';
import 'package:vibeo/features/auth/presentation/providers/auth_providers.dart';
import 'package:vibeo/features/auth/presentation/providers/guest_mode_provider.dart';

import '../../../helpers/fake_auth_repository.dart';

void main() {
  setUpAll(() {
    // Évite tout accès réseau aux polices pendant les tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<ProviderContainer> pumpAuth(
    WidgetTester tester,
    ThemeData theme,
    AuthRepository repo,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: theme, home: const AuthScreen()),
      ),
    );
    await tester.pump();
    return container;
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';
    testWidgets('AuthScreen se rend en thème $name', (tester) async {
      final theme = isDark ? AppTheme.dark : AppTheme.light;
      final repo = FakeAuthRepository();
      addTearDown(repo.dispose);
      await pumpAuth(tester, theme, repo);

      expect(find.text('Bienvenue sur Vibeo'), findsOneWidget);
      expect(find.text('Connexion'), findsOneWidget);
      expect(find.text('Inscription'), findsOneWidget);
      expect(find.text('Se connecter'), findsOneWidget);
      expect(find.text('Continuer avec Google'), findsOneWidget);
    });
  }

  testWidgets('bascule Inscription affiche le champ nom d\'utilisateur', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    addTearDown(repo.dispose);
    await pumpAuth(tester, AppTheme.dark, repo);

    expect(
      find.widgetWithText(TextFormField, 'Nom d\'utilisateur'),
      findsNothing,
    );

    await tester.tap(find.text('Inscription'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextFormField, 'Nom d\'utilisateur'),
      findsOneWidget,
    );
    expect(find.text('Créer mon compte'), findsOneWidget);
  });

  testWidgets('validation : soumission vide affiche les erreurs', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    addTearDown(repo.dispose);
    await pumpAuth(tester, AppTheme.dark, repo);

    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text('Entre ton email.'), findsOneWidget);
    expect(find.text('Entre ton mot de passe.'), findsOneWidget);
    // Aucune tentative de connexion ne doit avoir eu lieu.
    expect(repo.calls, isEmpty);
  });

  testWidgets('bouton « Continuer en tant qu\'invité » active le mode invité', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    addTearDown(repo.dispose);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    // `_continueAsGuest` rejoint l'accueil via go_router : un routeur minimal
    // est donc nécessaire ici (contrairement aux autres tests de cet écran).
    final router = GoRouter(
      initialLocation: AppRoutes.auth,
      routes: [
        GoRoute(path: AppRoutes.auth, builder: (_, _) => const AuthScreen()),
        GoRoute(
          path: AppRoutes.home,
          builder: (_, _) => const Scaffold(body: Text('Accueil (test)')),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();

    expect(find.text('Continuer en tant qu\'invité'), findsOneWidget);
    expect(container.read(guestModeProvider), isFalse);

    // Le bouton est en bas du formulaire, dans un SingleChildScrollView : il
    // faut le faire défiler à l'écran avant de pouvoir le taper.
    await tester.ensureVisible(find.text('Continuer en tant qu\'invité'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuer en tant qu\'invité'));
    await tester.pumpAndSettle();

    expect(container.read(guestModeProvider), isTrue);
  });
}
