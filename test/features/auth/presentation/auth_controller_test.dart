import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeo/features/auth/data/auth_repository.dart';
import 'package:vibeo/features/auth/presentation/providers/auth_controller.dart';
import 'package:vibeo/features/auth/presentation/providers/auth_providers.dart';

import '../../../helpers/fake_auth_repository.dart';

void main() {
  ProviderContainer makeContainer(AuthRepository repo) {
    return ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
    );
  }

  test('signIn réussi → renvoie true et état non erreur', () async {
    final repo = FakeAuthRepository();
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    addTearDown(repo.dispose);

    final ok = await container
        .read(authControllerProvider.notifier)
        .signIn(email: 'a@b.co', password: 'secret1');

    expect(ok, isTrue);
    expect(repo.calls, contains('signIn:a@b.co'));
    expect(container.read(authControllerProvider).hasError, isFalse);
  });

  test('signIn avec mauvais identifiants → message FR mappé', () async {
    final repo = FakeAuthRepository(
      throwOnSignIn: const AuthException('Invalid login credentials'),
    );
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    addTearDown(repo.dispose);

    final ok = await container
        .read(authControllerProvider.notifier)
        .signIn(email: 'a@b.co', password: 'wrong');

    expect(ok, isFalse);
    final state = container.read(authControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.error.toString(), 'Email ou mot de passe incorrect.');
  });

  test('signUp → indique qu\'une confirmation email est requise', () async {
    final repo = FakeAuthRepository();
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    addTearDown(repo.dispose);

    final outcome = await container
        .read(authControllerProvider.notifier)
        .signUp(email: 'a@b.co', password: 'secret1', username: 'alice_test');

    expect(outcome, isNotNull);
    expect(outcome!.needsEmailConfirmation, isTrue);
  });

  test('signUp avec email déjà pris → message FR mappé', () async {
    final repo = FakeAuthRepository(
      throwOnSignUp: const AuthException('User already registered'),
    );
    final container = makeContainer(repo);
    addTearDown(container.dispose);
    addTearDown(repo.dispose);

    final outcome = await container
        .read(authControllerProvider.notifier)
        .signUp(email: 'a@b.co', password: 'secret1', username: 'alice_test');

    expect(outcome, isNull);
    expect(
      container.read(authControllerProvider).error.toString(),
      'Un compte existe déjà avec cet email.',
    );
  });
}
