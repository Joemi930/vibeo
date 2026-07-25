import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/core/theme/theme_mode_provider.dart';
import 'package:vibeo/features/library/presentation/library_screen.dart';

void main() {
  setUpAll(() {
    // Évite tout accès réseau aux polices pendant les tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpLibrary(WidgetTester tester, ThemeData theme) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(theme: theme, home: const LibraryScreen()),
      ),
    );
    await tester.pump();
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';
    testWidgets('LibraryScreen se rend en thème $name sans overflow', (
      tester,
    ) async {
      await pumpLibrary(tester, isDark ? AppTheme.dark : AppTheme.light);

      expect(find.text('Bibliothèque'), findsNWidgets(2));
      expect(
        find.text('Tes playlists, abonnements et historique apparaîtront ici.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('LibraryScreen se rend sans overflow sur petite largeur', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpLibrary(tester, AppTheme.light);

    expect(tester.takeException(), isNull);
  });
}
