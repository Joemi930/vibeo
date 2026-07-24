import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeo/core/theme/theme_mode_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> makeContainer(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
  }

  test('valeur par défaut = système quand rien n\'est stocké', () async {
    final container = await makeContainer({});
    addTearDown(container.dispose);
    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('relit la valeur persistée au démarrage', () async {
    final container = await makeContainer({'theme_mode': 'dark'});
    addTearDown(container.dispose);
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('setMode met à jour l\'état ET persiste', () async {
    final container = await makeContainer({});
    addTearDown(container.dispose);

    await container.read(themeModeProvider.notifier).setMode(ThemeMode.light);
    expect(container.read(themeModeProvider), ThemeMode.light);

    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getString('theme_mode'), 'light');
  });
}
