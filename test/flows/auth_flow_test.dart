import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vibeo/core/router/app_routes.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/features/auth/presentation/auth_screen.dart';
import 'package:vibeo/features/auth/presentation/email_verification_screen.dart';
import 'package:vibeo/features/auth/presentation/providers/auth_providers.dart';

import '../helpers/fake_auth_repository.dart';

/// Parcours : depuis l'écran d'authentification, une inscription valide mène à
/// l'écran « Vérifie ta boîte mail ».
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('inscription valide → écran de vérification email', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    addTearDown(repo.dispose);

    final router = GoRouter(
      initialLocation: AppRoutes.auth,
      routes: [
        GoRoute(path: AppRoutes.auth, builder: (_, _) => const AuthScreen()),
        GoRoute(
          path: AppRoutes.emailVerification,
          builder: (_, state) => EmailVerificationScreen(
            email: state.extra is String ? state.extra as String : null,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // Passe en mode Inscription.
    await tester.tap(find.text('Inscription'));
    await tester.pumpAndSettle();

    // Remplit le formulaire.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nom d\'utilisateur'),
      'alice_test',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'alice@test.dev',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mot de passe'),
      'secret123',
    );

    // Soumet.
    await tester.tap(find.text('Créer mon compte'));
    await tester.pumpAndSettle();

    // On atterrit sur l'écran de vérification.
    expect(find.text('Vérifie ta boîte mail'), findsOneWidget);
    expect(find.textContaining('alice@test.dev'), findsOneWidget);
    expect(repo.calls, contains('signUp:alice@test.dev:alice_test'));
  });
}
