import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/core/theme/theme_mode_provider.dart';
import 'package:vibeo/core/widgets/theme_toggle_switch.dart';
import 'package:vibeo/core/widgets/vibeo_app_bar.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpBar(
    WidgetTester tester,
    ThemeData theme,
    PreferredSizeWidget appBar,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: theme,
          home: Scaffold(appBar: appBar, body: const SizedBox()),
        ),
      ),
    );
    await tester.pump();
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';

    testWidgets('affiche le titre fourni en thème $name', (tester) async {
      await pumpBar(
        tester,
        isDark ? AppTheme.dark : AppTheme.light,
        const VibeoAppBar(title: 'Mon écran'),
      );

      expect(find.text('Mon écran'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'affiche la flèche retour et l\'interrupteur de thème par défaut '
      '(thème $name)',
      (tester) async {
        await pumpBar(
          tester,
          isDark ? AppTheme.dark : AppTheme.light,
          const VibeoAppBar(title: 'Mon écran'),
        );

        expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
        expect(find.byType(ThemeToggleSwitch), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('n\'affiche pas la flèche retour quand showBack est false', (
    tester,
  ) async {
    await pumpBar(
      tester,
      AppTheme.dark,
      const VibeoAppBar(title: 'Accueil', showBack: false),
    );

    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
  });

  testWidgets(
    'n\'affiche pas l\'interrupteur de thème quand showThemeToggle est false',
    (tester) async {
      await pumpBar(
        tester,
        AppTheme.dark,
        const VibeoAppBar(title: 'X', showThemeToggle: false),
      );

      expect(find.byType(ThemeToggleSwitch), findsNothing);
    },
  );

  testWidgets(
    'taper la flèche dépile la route quand le Navigator peut le faire',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              appBar: const VibeoAppBar(title: 'Accueil', showBack: false),
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: const VibeoAppBar(title: 'Détail'),
                          body: const Text('Contenu du détail'),
                        ),
                      ),
                    ),
                    child: const Text('Ouvrir le détail'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Ouvrir le détail'));
      await tester.pumpAndSettle();

      expect(find.text('Détail'), findsOneWidget);
      expect(find.text('Contenu du détail'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Contenu du détail'), findsNothing);
      expect(find.text('Accueil'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
