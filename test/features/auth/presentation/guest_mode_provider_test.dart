import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeo/core/theme/theme_mode_provider.dart';
import 'package:vibeo/features/auth/presentation/providers/guest_mode_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> makeContainer(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    return container;
  }

  test('valeur par défaut = false quand rien n\'est stocké', () async {
    final container = await makeContainer({});
    addTearDown(container.dispose);

    expect(container.read(guestModeProvider), isFalse);
  });

  test('enable() met à true et écrit guest_mode dans les prefs', () async {
    final container = await makeContainer({});
    addTearDown(container.dispose);

    await container.read(guestModeProvider.notifier).enable();

    expect(container.read(guestModeProvider), isTrue);
    expect(
      container.read(sharedPreferencesProvider).getBool('guest_mode'),
      isTrue,
    );
  });

  test('disable() remet à false et écrit guest_mode dans les prefs', () async {
    final container = await makeContainer({'guest_mode': true});
    addTearDown(container.dispose);
    expect(container.read(guestModeProvider), isTrue);

    await container.read(guestModeProvider.notifier).disable();

    expect(container.read(guestModeProvider), isFalse);
    expect(
      container.read(sharedPreferencesProvider).getBool('guest_mode'),
      isFalse,
    );
  });

  test('relit la valeur true déjà stockée dans les prefs', () async {
    final container = await makeContainer({'guest_mode': true});
    addTearDown(container.dispose);

    expect(container.read(guestModeProvider), isTrue);
  });
}
