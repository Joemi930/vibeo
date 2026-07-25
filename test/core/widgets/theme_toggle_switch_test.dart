import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/core/theme/theme_mode_provider.dart';
import 'package:vibeo/core/widgets/theme_toggle_switch.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<ProviderContainer> pumpSwitch(
    WidgetTester tester,
    ThemeData theme, {
    Map<String, Object> initialPrefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme,
          home: const Scaffold(body: Center(child: ThemeToggleSwitch())),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';
    testWidgets('ThemeToggleSwitch se rend en thème $name', (tester) async {
      await pumpSwitch(
        tester,
        isDark ? AppTheme.dark : AppTheme.light,
        initialPrefs: {'theme_mode': isDark ? 'dark' : 'light'},
      );

      expect(find.byType(ThemeToggleSwitch), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('un tap fait passer le thème de sombre à clair et persiste', (
    tester,
  ) async {
    final container = await pumpSwitch(
      tester,
      AppTheme.dark,
      initialPrefs: {'theme_mode': 'dark'},
    );
    expect(container.read(themeModeProvider), ThemeMode.dark);

    await tester.tap(find.byType(ThemeToggleSwitch));
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(
      container.read(sharedPreferencesProvider).getString('theme_mode'),
      'light',
    );
  });

  testWidgets('un tap fait passer le thème de clair à sombre et persiste', (
    tester,
  ) async {
    final container = await pumpSwitch(
      tester,
      AppTheme.light,
      initialPrefs: {'theme_mode': 'light'},
    );
    expect(container.read(themeModeProvider), ThemeMode.light);

    await tester.tap(find.byType(ThemeToggleSwitch));
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(
      container.read(sharedPreferencesProvider).getString('theme_mode'),
      'dark',
    );
  });

  testWidgets(
    'depuis le mode système, un tap bascule vers un mode explicite et '
    'persiste',
    (tester) async {
      // Sans préférence stockée, le mode par défaut est « système ». Dans
      // l'environnement de test, la luminosité de plateforme est claire :
      // un tap doit donc basculer vers le sombre.
      final container = await pumpSwitch(tester, AppTheme.light);
      expect(container.read(themeModeProvider), ThemeMode.system);

      await tester.tap(find.byType(ThemeToggleSwitch));
      await tester.pumpAndSettle();

      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(
        container.read(sharedPreferencesProvider).getString('theme_mode'),
        'dark',
      );
    },
  );
}
