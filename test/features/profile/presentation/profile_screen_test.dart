import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/features/auth/domain/profile.dart';
import 'package:vibeo/features/auth/domain/user_role.dart';
import 'package:vibeo/features/auth/presentation/providers/auth_providers.dart';
import 'package:vibeo/features/profile/presentation/profile_screen.dart';
import 'package:vibeo/features/profile/presentation/providers/profile_providers.dart';

import '../../../helpers/fake_auth_repository.dart';

void main() {
  setUpAll(() {
    // Évite tout accès réseau aux polices pendant les tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final baseProfile = Profile(
    id: 'user-1',
    username: 'tester',
    displayName: 'Testeur Vibeo',
    bio: 'Fan de clips et de découvertes musicales.',
    role: UserRole.listener,
    createdAt: DateTime(2026, 1, 1),
  );

  Future<ProviderContainer> pumpProfile(
    WidgetTester tester,
    ThemeData theme, {
    Profile? profile,
    bool useError = false,
  }) async {
    final repo = FakeAuthRepository();
    addTearDown(repo.dispose);
    final container = ProviderContainer(
      // Désactive le retry automatique de Riverpod pour que l'état d'erreur
      // se stabilise immédiatement dans les tests (sinon il reste en
      // AsyncLoading(error: ...) le temps du backoff exponentiel).
      retry: (retryCount, error) => null,
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        if (useError)
          currentProfileProvider.overrideWith(
            (ref) => Future<Profile?>.error(Exception('boom')),
          )
        else
          currentProfileProvider.overrideWith((ref) => profile),
        avatarSignedUrlProvider.overrideWith((ref, path) => null),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: theme, home: const ProfileScreen()),
      ),
    );
    await tester.pump();
    return container;
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';
    testWidgets('ProfileScreen se rend en thème $name sans overflow', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        isDark ? AppTheme.dark : AppTheme.light,
        profile: baseProfile,
      );

      expect(find.text('Profil'), findsOneWidget);
      expect(find.text('Testeur Vibeo'), findsOneWidget);
      expect(find.text('@tester'), findsOneWidget);
      expect(find.text('Auditeur'), findsOneWidget);
      expect(
        find.text('Fan de clips et de découvertes musicales.'),
        findsOneWidget,
      );
      expect(find.text('Modifier le profil'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'ProfileScreen (artiste, nom/bio longs) se rend sans overflow sur petite largeur',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final longProfile = Profile(
        id: 'user-2',
        username: 'un-nom-utilisateur-assez-long-pour-tester',
        displayName: 'Un Nom Affiché Vraiment Très Long Pour Vérifier Le Rendu',
        bio:
            'Une biographie particulièrement longue destinée à vérifier que '
            'le texte se replie correctement sans provoquer le moindre '
            'débordement visuel (RenderFlex overflow) sur un petit écran '
            'de type mobile en orientation portrait.',
        role: UserRole.artist,
        createdAt: DateTime(2026, 1, 1),
      );

      await pumpProfile(tester, AppTheme.light, profile: longProfile);

      expect(find.text('Artiste vérifié'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ProfileScreen affiche le chargement sans overflow', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    addTearDown(repo.dispose);
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        currentProfileProvider.overrideWith(
          (ref) => Completer<Profile?>().future,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.dark, home: const ProfileScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ProfileScreen affiche une erreur sans overflow', (tester) async {
    await pumpProfile(tester, AppTheme.light, useError: true);
    await tester.pump();

    expect(find.text('Impossible de charger le profil.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('« Modifier le profil » ouvre la feuille d\'édition', (
    tester,
  ) async {
    await pumpProfile(tester, AppTheme.dark, profile: baseProfile);

    await tester.tap(find.text('Modifier le profil'));
    await tester.pumpAndSettle();

    expect(find.text('Modifier le profil'), findsWidgets);
    expect(find.widgetWithText(TextFormField, 'Nom affiché'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Bio'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
