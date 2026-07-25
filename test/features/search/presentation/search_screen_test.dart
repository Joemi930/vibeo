import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/core/theme/theme_mode_provider.dart';
import 'package:vibeo/features/search/presentation/search_screen.dart';

void main() {
  setUpAll(() {
    // Évite tout accès réseau aux polices pendant les tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpSearch(WidgetTester tester, ThemeData theme) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(theme: theme, home: const SearchScreen()),
      ),
    );
    await tester.pump();
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';
    testWidgets('SearchScreen se rend en thème $name sans overflow', (
      tester,
    ) async {
      await pumpSearch(tester, isDark ? AppTheme.dark : AppTheme.light);

      expect(find.text('Recherche'), findsNWidgets(2));
      expect(
        find.text('Recherche de clips et d\'artistes à venir.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('SearchScreen se rend sans overflow sur petite largeur', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpSearch(tester, AppTheme.light);

    expect(tester.takeException(), isNull);
  });
}
