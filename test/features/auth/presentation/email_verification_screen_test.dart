import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/core/theme/theme_mode_provider.dart';
import 'package:vibeo/features/auth/presentation/email_verification_screen.dart';

void main() {
  setUpAll(() {
    // Évite tout accès réseau aux polices pendant les tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpEmailVerification(
    WidgetTester tester,
    ThemeData theme, {
    String? email,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: theme,
          home: EmailVerificationScreen(email: email),
        ),
      ),
    );
    await tester.pump();
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';
    testWidgets(
      'EmailVerificationScreen (sans email) se rend en thème $name sans overflow',
      (tester) async {
        await pumpEmailVerification(
          tester,
          isDark ? AppTheme.dark : AppTheme.light,
        );

        expect(find.text('Vérifie ta boîte mail'), findsOneWidget);
        expect(
          find.text(
            'Nous t\'avons envoyé un lien de confirmation. '
            'Clique dessus pour activer ton compte.',
          ),
          findsOneWidget,
        );
        expect(find.text('Revenir à la connexion'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'EmailVerificationScreen (avec email) se rend en thème $name sans overflow',
      (tester) async {
        // Plus de contenu depuis l'ajout du message « Si tu possèdes déjà… »
        tester.view.physicalSize = const Size(400, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await pumpEmailVerification(
          tester,
          isDark ? AppTheme.dark : AppTheme.light,
          email: 'artiste.exemple@vibeo.test',
        );

        expect(find.text('Vérifie ta boîte mail'), findsOneWidget);
        expect(
          find.text(
            'Un lien de confirmation a été envoyé à '
            'artiste.exemple@vibeo.test. '
            'Vérifie ta boîte de réception (et tes spams).',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'EmailVerificationScreen se rend sans overflow avec un email long sur petite largeur',
    (tester) async {
      tester.view.physicalSize = const Size(320, 750);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpEmailVerification(
        tester,
        AppTheme.light,
        email: 'un.tres.long.nom.utilisateur.artiste@domaine-vibeo-test.com',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
