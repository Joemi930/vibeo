import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/core/theme/theme_mode_provider.dart';
import 'package:vibeo/features/auth/presentation/providers/auth_providers.dart';
import 'package:vibeo/features/settings/presentation/settings_screen.dart';

import '../../../helpers/fake_auth_repository.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<ProviderContainer> pumpSettings(
    WidgetTester tester,
    ThemeData theme,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeAuthRepository();
    addTearDown(repo.dispose);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: theme, home: const SettingsScreen()),
      ),
    );
    await tester.pump();
    return container;
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';
    testWidgets('SettingsScreen se rend en thème $name', (tester) async {
      await pumpSettings(tester, isDark ? AppTheme.dark : AppTheme.light);
      expect(find.text('APPARENCE'), findsOneWidget);
      expect(find.text('Sombre'), findsOneWidget);
      expect(find.text('Clair'), findsOneWidget);
      expect(find.text('Système'), findsOneWidget);
      expect(find.text('Se déconnecter'), findsOneWidget);
      expect(find.text('Supprimer mon compte'), findsOneWidget);
    });
  }

  testWidgets('sélectionner « Clair » met à jour le thème', (tester) async {
    final container = await pumpSettings(tester, AppTheme.dark);
    expect(container.read(themeModeProvider), ThemeMode.system);

    await tester.tap(find.text('Clair'));
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(
      container.read(sharedPreferencesProvider).getString('theme_mode'),
      'light',
    );
  });
}
