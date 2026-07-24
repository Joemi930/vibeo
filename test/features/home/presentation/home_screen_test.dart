import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/features/home/presentation/home_screen.dart';

void main() {
  setUpAll(() {
    // Évite tout accès réseau aux polices pendant les tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpHome(WidgetTester tester, ThemeData theme) async {
    await tester.pumpWidget(
      MaterialApp(theme: theme, home: const HomeScreen()),
    );
    await tester.pump();
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';
    testWidgets('HomeScreen se rend en thème $name sans overflow', (
      tester,
    ) async {
      await pumpHome(tester, isDark ? AppTheme.dark : AppTheme.light);

      expect(find.text('Vibeo'), findsOneWidget);
      expect(find.text('Accueil'), findsOneWidget);
      expect(
        find.text('Tes clips et recommandations apparaîtront ici.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('HomeScreen se rend sans overflow sur petite largeur', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpHome(tester, AppTheme.light);

    expect(tester.takeException(), isNull);
  });
}
