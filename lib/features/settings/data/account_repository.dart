import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/legal_identity.dart';

/// Levée quand `username` est déjà pris par un autre compte (violation de
/// l'unicité `profiles.username`, code Postgres `23505`).
///
/// Distinguée explicitement pour donner un message clair sans jamais montrer
/// le message brut de la `PostgrestException` sous-jacente (il révélerait le
/// nom de la contrainte / du schéma).
class UsernameTakenException implements Exception {
  const UsernameTakenException();
}

/// Contrat d'accès aux données de « Compte et confidentialité » : identité
/// civile, nom de scène/nom d'utilisateur, email, mot de passe, bannière de
/// profil et suppression de compte.
///
/// Volontairement séparé de `AuthRepository` (features/auth/data) : ce
/// contrat ne touche que des besoins propres aux Paramètres, sans modifier
/// l'abstraction d'authentification existante.
abstract class AccountRepository {
  /// Identité civile de l'utilisateur (null si jamais renseignée).
  Future<LegalIdentity?> fetchIdentity(String userId);

  /// Crée ou met à jour l'identité civile (upsert sur `user_identities`).
  Future<LegalIdentity> saveIdentity({
    required String userId,
    required String legalFirstName,
    required String legalLastName,
    String? legalMiddleName,
  });

  /// Met à jour le nom de scène (`display_name`, public, peut être vide pour
  /// retomber sur `username`) et le nom d'utilisateur (`username`, unique).
  ///
  /// Lève [UsernameTakenException] si `username` est déjà pris.
  Future<void> updateScreenName({
    required String userId,
    required String? displayName,
    required String username,
  });

  /// Téléverse une nouvelle bannière de profil dans le bucket privé `avatars`
  /// (chemin `<userId>/banner.<ext>`) et met à jour `profiles.banner_path`.
  /// Retourne le chemin de stockage.
  Future<String> uploadBanner({
    required String userId,
    required List<int> bytes,
    required String fileExtension,
    required String contentType,
  });

  /// Change l'email du compte. Supabase envoie un mail de confirmation à la
  /// **nouvelle** adresse ; le changement n'est effectif qu'après clic sur ce
  /// lien (l'email courant reste actif jusque-là).
  Future<void> updateEmail(String newEmail);

  /// Change le mot de passe du compte connecté.
  Future<void> updatePassword(String newPassword);

  /// Supprime définitivement le compte connecté via l'Edge Function
  /// `delete-account` (seule voie possible : la suppression d'un compte
  /// `auth.users` exige `service_role`, qui ne doit jamais approcher le code
  /// Flutter).
  Future<void> deleteAccount();
}

/// Implémentation basée sur `supabase_flutter`.
class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository(this._client);

  final SupabaseClient _client;

  static const String _avatarsBucket = 'avatars';
  static const int _usernameUniqueViolation = 23505;

  @override
  Future<LegalIdentity?> fetchIdentity(String userId) async {
    final row = await _client
        .from('user_identities')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return LegalIdentity.fromJson(row);
  }

  @override
  Future<LegalIdentity> saveIdentity({
    required String userId,
    required String legalFirstName,
    required String legalLastName,
    String? legalMiddleName,
  }) async {
    final row = await _client
        .from('user_identities')
        .upsert({
          'user_id': userId,
          'legal_first_name': legalFirstName,
          'legal_last_name': legalLastName,
          'legal_middle_name': legalMiddleName,
        })
        .select()
        .single();
    return LegalIdentity.fromJson(row);
  }

  @override
  Future<void> updateScreenName({
    required String userId,
    required String? displayName,
    required String username,
  }) async {
    try {
      await _client
          .from('profiles')
          .update({'display_name': displayName, 'username': username})
          .eq('id', userId);
    } on PostgrestException catch (e) {
      if (_isUniqueViolation(e)) {
        throw const UsernameTakenException();
      }
      rethrow;
    }
  }

  bool _isUniqueViolation(PostgrestException e) {
    // `code` est une chaîne SQLSTATE ('23505') côté postgrest-dart.
    return e.code == '$_usernameUniqueViolation';
  }

  @override
  Future<String> uploadBanner({
    required String userId,
    required List<int> bytes,
    required String fileExtension,
    required String contentType,
  }) async {
    final path = '$userId/banner.$fileExtension';
    await _client.storage
        .from(_avatarsBucket)
        .uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    await _client
        .from('profiles')
        .update({'banner_path': path})
        .eq('id', userId);
    return path;
  }

  @override
  Future<void> updateEmail(String newEmail) async {
    await _client.auth.updateUser(UserAttributes(email: newEmail));
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  @override
  Future<void> deleteAccount() async {
    // Aucun identifiant transmis dans le corps : l'Edge Function lit le
    // compte à supprimer depuis le JWT porté par l'appel (Authorization),
    // jamais depuis une valeur fournie par le client.
    await _client.functions.invoke('delete-account');
  }
}
