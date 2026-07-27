import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/auth_repository.dart';
import 'auth_providers.dart';

/// Résultat d'une inscription : indique si une confirmation par email est
/// requise (aucune session ouverte immédiatement).
class SignUpOutcome {
  const SignUpOutcome({required this.needsEmailConfirmation});
  final bool needsEmailConfirmation;
}

/// Contrôleur des actions d'authentification. Expose un état asynchrone
/// (`loading` / `error`) consommé par les écrans pour afficher spinner et
/// messages d'erreur en français.
class AuthController extends AsyncNotifier<void> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<void> build() async {}

  /// Connexion email/mot de passe. Retourne true si réussie.
  Future<bool> signIn({required String email, required String password}) async {
    state = const AsyncLoading();
    try {
      await _repo.signIn(email: email.trim(), password: password);
      state = const AsyncData(null);
      return true;
    } on AuthException catch (e, st) {
      state = AsyncError(_mapMessage(e), st);
      return false;
    } catch (e, st) {
      state = AsyncError(_genericError, st);
      return false;
    }
  }

  /// Inscription email/mot de passe. Retourne l'issue (confirmation requise ?).
  Future<SignUpOutcome?> signUp({
    required String email,
    required String password,
    required String username,
    String? emailRedirectTo,
  }) async {
    state = const AsyncLoading();
    try {
      final res = await _repo.signUp(
        email: email.trim(),
        password: password,
        username: username.trim(),
        emailRedirectTo: emailRedirectTo,
      );
      state = const AsyncData(null);
      return SignUpOutcome(needsEmailConfirmation: res.session == null);
    } on AuthException catch (e, st) {
      state = AsyncError(_mapMessage(e), st);
      return null;
    } catch (e, st) {
      state = AsyncError(_genericError, st);
      return null;
    }
  }

  /// Lance la connexion Google (OAuth).
  Future<bool> signInWithGoogle() async {
    state = const AsyncLoading();
    try {
      final ok = await _repo.signInWithGoogle();
      state = const AsyncData(null);
      return ok;
    } on AuthException catch (e, st) {
      state = AsyncError(_mapMessage(e), st);
      return false;
    } catch (e, st) {
      state = AsyncError(_genericError, st);
      return false;
    }
  }

  /// Envoie un email de réinitialisation de mot de passe.
  Future<bool> sendPasswordReset(String email, {String? redirectTo}) async {
    state = const AsyncLoading();
    try {
      await _repo.sendPasswordReset(email.trim(), redirectTo: redirectTo);
      state = const AsyncData(null);
      return true;
    } on AuthException catch (e, st) {
      state = AsyncError(_mapMessage(e), st);
      return false;
    } catch (e, st) {
      state = AsyncError(_genericError, st);
      return false;
    }
  }

  /// Déconnexion. Invalide aussi le profil en cache : sans cela, un compte
  /// admin qui se déconnecte laisse son rôle en mémoire, et l'utilisateur
  /// suivant qui se connecte avec un compte standard voit encore le dashboard
  /// le temps que le profil soit rechargé.
  Future<void> signOut() async {
    state = const AsyncLoading();
    try {
      await _repo.signOut();
      ref.invalidate(currentProfileProvider);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(_genericError, st);
    }
  }

  static const String _genericError =
      'Une erreur est survenue. Réessaie dans un instant.';

  /// Traduit les erreurs Supabase courantes en messages FR lisibles.
  static String _mapMessage(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials')) {
      return 'Email ou mot de passe incorrect.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Confirme d\'abord ton email via le lien reçu.';
    }
    if (msg.contains('user already registered') ||
        msg.contains('already been registered')) {
      return 'Un compte existe déjà avec cet email.';
    }
    if (msg.contains('password') && msg.contains('should be')) {
      return 'Le mot de passe est trop court (6 caractères minimum).';
    }
    if (msg.contains('rate limit') || msg.contains('too many')) {
      return 'Trop de tentatives. Réessaie dans quelques minutes.';
    }
    return e.message;
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(
  AuthController.new,
);
