import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/utils/dev_log.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/account_repository.dart';
import '../../domain/legal_identity.dart';

/// Fournit le [AccountRepository] concret (surchargeable en test).
final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return SupabaseAccountRepository(ref.watch(supabaseClientProvider));
});

/// Identité civile de l'utilisateur connecté (null si jamais renseignée ou
/// déconnecté).
final currentIdentityProvider = FutureProvider<LegalIdentity?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final repo = ref.watch(accountRepositoryProvider);
  return repo.fetchIdentity(user.id);
});

/// Contrôleur des actions de « Compte et confidentialité » : identité civile,
/// nom de scène/nom d'utilisateur, bannière, email, mot de passe, suppression
/// de compte.
class AccountController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Enregistre l'identité civile (prénom, nom, post-nom optionnel).
  Future<bool> saveIdentity({
    required String userId,
    required String legalFirstName,
    required String legalLastName,
    String? legalMiddleName,
  }) => _run(() async {
    await ref
        .read(accountRepositoryProvider)
        .saveIdentity(
          userId: userId,
          legalFirstName: legalFirstName,
          legalLastName: legalLastName,
          legalMiddleName: legalMiddleName,
        );
    ref.invalidate(currentIdentityProvider);
  });

  /// Met à jour le nom de scène et le nom d'utilisateur.
  ///
  /// Retourne un message d'erreur dédié (nom d'utilisateur déjà pris) plutôt
  /// que le générique, sans jamais exposer le détail brut de l'exception
  /// Postgres.
  Future<bool> updateScreenName({
    required String userId,
    String? displayName,
    required String username,
  }) => _run(() async {
    await ref
        .read(accountRepositoryProvider)
        .updateScreenName(
          userId: userId,
          displayName: displayName,
          username: username,
        );
    ref.invalidate(currentProfileProvider);
  }, usernameConflictMessage: 'Ce nom d\'utilisateur est déjà pris.');

  /// Téléverse une nouvelle bannière de profil.
  Future<bool> uploadBanner({
    required String userId,
    required List<int> bytes,
    required String fileExtension,
    required String contentType,
  }) => _run(() async {
    await ref
        .read(accountRepositoryProvider)
        .uploadBanner(
          userId: userId,
          bytes: bytes,
          fileExtension: fileExtension,
          contentType: contentType,
        );
    ref.invalidate(currentProfileProvider);
    ref.invalidate(avatarSignedUrlProvider);
  });

  /// Change l'email du compte. Un mail de confirmation part sur la
  /// **nouvelle** adresse ; l'ancienne reste active tant qu'il n'est pas
  /// confirmé.
  Future<bool> changeEmail(String newEmail) =>
      _run(() => ref.read(accountRepositoryProvider).updateEmail(newEmail));

  /// Change le mot de passe du compte connecté.
  Future<bool> changePassword(String newPassword) => _run(
    () => ref.read(accountRepositoryProvider).updatePassword(newPassword),
  );

  /// Supprime définitivement le compte connecté.
  Future<bool> deleteAccount() =>
      _run(() => ref.read(accountRepositoryProvider).deleteAccount());

  /// Exécute [action] en pilotant l'état `loading`/`error`/`data`, en
  /// traduisant les erreurs connues en français et en journalisant le détail
  /// technique via [logError] (jamais affiché à l'utilisateur).
  Future<bool> _run(
    Future<void> Function() action, {
    String? usernameConflictMessage,
  }) async {
    state = const AsyncLoading();
    try {
      await action();
      state = const AsyncData(null);
      return true;
    } on UsernameTakenException catch (e, st) {
      state = AsyncError(
        usernameConflictMessage ?? 'Ce nom d\'utilisateur est déjà pris.',
        st,
      );
      logError('AccountController', e, st);
      return false;
    } on AuthException catch (e, st) {
      state = AsyncError(_mapAuthMessage(e), st);
      logError('AccountController', e, st);
      return false;
    } catch (e, st) {
      state = AsyncError(_genericError, st);
      logError('AccountController', e, st);
      return false;
    }
  }

  static const String _genericError =
      'Une erreur est survenue. Réessaie dans un instant.';

  static String _mapAuthMessage(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('password') && msg.contains('should be')) {
      return 'Le mot de passe est trop court (6 caractères minimum).';
    }
    if (msg.contains('email') && msg.contains('already')) {
      return 'Un compte existe déjà avec cet email.';
    }
    if (msg.contains('same') && msg.contains('email')) {
      return 'C\'est déjà ton adresse actuelle.';
    }
    if (msg.contains('rate limit') || msg.contains('too many')) {
      return 'Trop de tentatives. Réessaie dans quelques minutes.';
    }
    return _genericError;
  }
}

final accountControllerProvider =
    AsyncNotifierProvider<AccountController, void>(AccountController.new);
