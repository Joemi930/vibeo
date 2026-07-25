import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeo/core/auth/require_auth.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/features/auth/presentation/providers/auth_providers.dart';

import '../../helpers/fake_auth_repository.dart';

/// Utilisateur factice pour simuler un compte connecté sans passer par
/// Supabase : seuls les champs requis par [User] sont renseignés.
final _fakeUser = User(
  id: 'user-1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime(2026, 1, 1).toIso8601String(),
);

/// Petit écran hôte qui déclenche [requireAuth] au tap et journalise le
/// résultat, pour vérifier le comportement sans dépendre d'un vrai écran.
class _Harness extends ConsumerWidget {
  const _Harness({required this.gate, required this.onResult});

  final AuthGate gate;
  final ValueChanged<bool> onResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final ok = await requireAuth(context, ref, gate: gate);
            onResult(ok);
          },
          child: const Text('Agir'),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpHarness(
    WidgetTester tester,
    ThemeData theme, {
    required AuthGate gate,
    required FakeAuthRepository repo,
    required ValueChanged<bool> onResult,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: theme,
          home: _Harness(gate: gate, onResult: onResult),
        ),
      ),
    );
    await tester.pump();
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';

    testWidgets(
      'utilisateur connecté : requireAuth renvoie true sans ouvrir de feuille '
      '(thème $name)',
      (tester) async {
        final repo = FakeAuthRepository(initialUser: _fakeUser);
        addTearDown(repo.dispose);
        bool? result;

        await pumpHarness(
          tester,
          isDark ? AppTheme.dark : AppTheme.light,
          gate: AuthGate.like,
          repo: repo,
          onResult: (ok) => result = ok,
        );

        await tester.tap(find.text('Agir'));
        await tester.pumpAndSettle();

        expect(result, isTrue);
        expect(find.textContaining('Connecte-toi pour'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'utilisateur déconnecté : requireAuth renvoie false et ouvre la feuille '
      '(thème $name)',
      (tester) async {
        final repo = FakeAuthRepository();
        addTearDown(repo.dispose);
        bool? result;

        await pumpHarness(
          tester,
          isDark ? AppTheme.dark : AppTheme.light,
          gate: AuthGate.like,
          repo: repo,
          onResult: (ok) => result = ok,
        );

        await tester.tap(find.text('Agir'));
        await tester.pumpAndSettle();

        expect(find.text('Connecte-toi pour aimer ce clip'), findsOneWidget);
        expect(find.text('Se connecter'), findsOneWidget);
        expect(find.text('Créer un compte'), findsOneWidget);
        expect(find.text('Plus tard'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Ferme la feuille pour que le futur de requireAuth se résolve.
        await tester.tap(find.text('Plus tard'));
        await tester.pumpAndSettle();

        expect(result, isFalse);
      },
    );
  }

  testWidgets('affiche la phrase adaptée à AuthGate.comment', (tester) async {
    final repo = FakeAuthRepository();
    addTearDown(repo.dispose);

    await pumpHarness(
      tester,
      AppTheme.dark,
      gate: AuthGate.comment,
      repo: repo,
      onResult: (_) {},
    );

    await tester.tap(find.text('Agir'));
    await tester.pumpAndSettle();

    expect(find.text('Connecte-toi pour commenter'), findsOneWidget);

    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();
  });
}
