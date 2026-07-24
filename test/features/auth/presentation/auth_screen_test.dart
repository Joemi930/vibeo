import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/features/auth/data/auth_repository.dart';
import 'package:vibeo/features/auth/presentation/auth_screen.dart';
import 'package:vibeo/features/auth/presentation/providers/auth_providers.dart';

import '../../../helpers/fake_auth_repository.dart';

void main() {
  setUpAll(() {
    // Évite tout accès réseau aux polices pendant les tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpAuth(
    WidgetTester tester,
    ThemeData theme,
    AuthRepository repo,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(theme: theme, home: const AuthScreen()),
      ),
    );
    await tester.pump();
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
}
