import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeo/core/router/app_routes.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/core/theme/theme_mode_provider.dart';
import 'package:vibeo/features/auth/domain/profile.dart';
import 'package:vibeo/features/auth/domain/user_role.dart';
import 'package:vibeo/features/auth/presentation/providers/auth_providers.dart';
import 'package:vibeo/features/profile/presentation/providers/profile_providers.dart';
import 'package:vibeo/features/settings/presentation/account_privacy_screen.dart';
import 'package:vibeo/features/settings/presentation/providers/account_providers.dart';
import 'package:vibeo/features/settings/presentation/widgets/delete_account_section.dart';

import '../../../helpers/fake_account_repository.dart';
import '../../../helpers/fake_auth_repository.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final profile = Profile(
    id: 'user-1',
    username: 'naika',
    displayName: 'Naïka',
    role: UserRole.listener,
    createdAt: DateTime(2026, 1, 1),
  );

  final user = User(
    id: 'user-1',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
    email: 'naika@example.test',
  );

  Future<(ProviderContainer container, FakeAccountRepository accountRepo)>
  pumpScreen(WidgetTester tester, {bool throwUsernameTaken = false}) async {
    // Toutes les sections (identité, nom de scène, email, mot de passe,
    // suppression) doivent tenir sans défiler pour que les tests puissent
    // taper directement dessus.
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final authRepo = FakeAuthRepository(initialUser: user);
    addTearDown(authRepo.dispose);
    final accountRepo = FakeAccountRepository(
      throwUsernameTaken: throwUsernameTaken,
    );

    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(authRepo),
        accountRepositoryProvider.overrideWithValue(accountRepo),
        currentProfileProvider.overrideWith((ref) async => profile),
        currentIdentityProvider.overrideWith((ref) async => null),
        avatarSignedUrlProvider.overrideWith((ref, path) async => null),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const AccountPrivacyScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (container, accountRepo);
  }

  testWidgets('affiche les sections de « Compte et confidentialité »', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Identité civile'), findsOneWidget);
    expect(find.text('Nom de scène et nom d\'utilisateur'), findsOneWidget);
    expect(find.text('Adresse email'), findsOneWidget);
    expect(find.text('Mot de passe'), findsOneWidget);
    expect(find.text('Supprimer mon compte'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('l\'identité civile ne se soumet pas si le prénom est vide', (
    tester,
  ) async {
    final (_, accountRepo) = await pumpScreen(tester);

    await tester.tap(
      find.widgetWithText(FilledButton, 'Enregistrer l\'identité'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Champ obligatoire.'), findsWidgets);
    expect(accountRepo.calls, isEmpty);
  });

  testWidgets(
    'le nom d\'utilisateur trop court (< 4) bloque l\'enregistrement',
    (tester) async {
      final (_, accountRepo) = await pumpScreen(tester);

      final usernameField = find.widgetWithText(
        TextFormField,
        'Nom d\'utilisateur',
      );
      await tester.enterText(usernameField, 'abc');
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer').first);
      await tester.pumpAndSettle();

      expect(find.text('4 caractères minimum.'), findsOneWidget);
      expect(accountRepo.calls, isEmpty);
    },
  );

  testWidgets(
    'le nom d\'utilisateur valide déclenche l\'appel repo et gère le conflit',
    (tester) async {
      final (_, accountRepo) = await pumpScreen(
        tester,
        throwUsernameTaken: true,
      );

      final usernameField = find.widgetWithText(
        TextFormField,
        'Nom d\'utilisateur',
      );
      await tester.enterText(usernameField, 'nouveau_nom');
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer').first);
      await tester.pumpAndSettle();

      expect(
        accountRepo.calls,
        contains('updateScreenName:user-1:nouveau_nom'),
      );
      expect(find.text('Ce nom d\'utilisateur est déjà pris.'), findsOneWidget);
    },
  );

  testWidgets(
    'la suppression de compte exige la saisie exacte du nom d\'utilisateur',
    (tester) async {
      final (_, accountRepo) = await pumpScreen(tester);

      await tester.tap(find.text('Supprimer le compte'));
      await tester.pumpAndSettle();

      expect(find.text('Supprimer définitivement le compte'), findsOneWidget);

      // Le bouton de confirmation est désactivé tant que la saisie ne
      // correspond pas exactement au nom d'utilisateur.
      var confirmButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Supprimer définitivement'),
      );
      expect(confirmButton.onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'Confirme le nom d\'utilisateur'),
        'pas-le-bon-nom',
      );
      await tester.pump();
      confirmButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Supprimer définitivement'),
      );
      expect(confirmButton.onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'Confirme le nom d\'utilisateur'),
        profile.username,
      );
      await tester.pump();
      confirmButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Supprimer définitivement'),
      );
      expect(confirmButton.onPressed, isNotNull);

      expect(accountRepo.calls, isEmpty);
    },
  );

  testWidgets(
    'DeleteAccountSection isolée : confirmation saisie déclenche deleteAccount',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final accountRepo = FakeAccountRepository();
      final authRepo = FakeAuthRepository(initialUser: user);
      addTearDown(authRepo.dispose);
      final container = ProviderContainer(
        retry: (retryCount, error) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authRepositoryProvider.overrideWithValue(authRepo),
          accountRepositoryProvider.overrideWithValue(accountRepo),
        ],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/settings-test',
        routes: [
          GoRoute(
            path: '/settings-test',
            builder: (_, _) =>
                const Scaffold(body: DeleteAccountSection(username: 'naika')),
          ),
          GoRoute(
            path: AppRoutes.auth,
            builder: (_, _) => const Scaffold(body: Text('Auth')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Supprimer le compte'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Confirme le nom d\'utilisateur'),
        'naika',
      );
      await tester.pump();

      await tester.tap(find.text('Supprimer définitivement'));
      await tester.pumpAndSettle();

      expect(accountRepo.calls, contains('deleteAccount'));
    },
  );
}
