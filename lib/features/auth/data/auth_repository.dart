import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../domain/profile.dart';

/// Schéma de redirection deep-link utilisé pour l'OAuth (Google) sur mobile.
/// Doit correspondre à l'intent-filter Android et être ajouté à l'allow-list
/// « Redirect URLs » du projet Supabase.
const String kOAuthRedirectMobile = 'io.vibeo.app://login-callback/';

/// Contrat d'accès à l'authentification et au profil. L'abstraction permet de
/// fournir une implémentation mockée dans les tests (aucun appel réseau).
abstract class AuthRepository {
  /// Session courante (null si déconnecté).
  Session? get currentSession;

  /// Utilisateur courant (null si déconnecté).
  User? get currentUser;

  /// Flux des changements d'état d'authentification.
  Stream<AuthState> get onAuthStateChange;

  /// Inscription par email/mot de passe. Le `username` est transmis en
  /// métadonnées pour le trigger de création de profil. Un email de
  /// vérification est envoyé (redirection [emailRedirectTo]).
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
    String? emailRedirectTo,
  });

  /// Connexion par email/mot de passe.
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  });

  /// Connexion via Google (OAuth). Redirection web par défaut ; deep-link sur
  /// mobile.
  Future<bool> signInWithGoogle();

  /// Envoie un email de réinitialisation de mot de passe.
  Future<void> sendPasswordReset(String email, {String? redirectTo});

  /// Déconnexion.
  Future<void> signOut();

  /// Récupère le profil de l'utilisateur donné (null si absent).
  Future<Profile?> fetchProfile(String userId);

  /// Met à jour les champs modifiables du profil et retourne la version à jour.
  Future<Profile> updateProfile({
    required String userId,
    String? displayName,
    String? bio,
    String? avatarUrl,
  });

  /// Téléverse l'avatar de l'utilisateur dans le bucket privé `avatars` (chemin
  /// `<userId>/avatar.<ext>`) et retourne le chemin de stockage (à conserver
  /// dans `profiles.avatar_url`).
  Future<String> uploadAvatar({
    required String userId,
    required List<int> bytes,
    required String fileExtension,
    required String contentType,
  });

  /// Génère une URL signée temporaire pour afficher un avatar stocké (bucket
  /// privé). Retourne null si le chemin est vide.
  Future<String?> signedAvatarUrl(String? storagePath, {int expiresInSeconds});
}

/// Implémentation basée sur `supabase_flutter`.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  @override
  Session? get currentSession => _auth.currentSession;

  @override
  User? get currentUser => _auth.currentUser;

  @override
  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
    String? emailRedirectTo,
  }) {
    return _auth.signUp(
      email: email,
      password: password,
      data: {'username': username},
      emailRedirectTo: emailRedirectTo,
    );
  }

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<bool> signInWithGoogle() {
    // Sur le web, on renseigne explicitement l'URL de redirection pour que
    // Supabase sache où renvoyer l'utilisateur après l'authentification Google.
    // Sans cela, Supabase utilise sa SITE_URL interne, qui peut ne pas être
    // configurée ou pointer vers localhost.
    final webRedirect = kIsWeb && Env.webBaseUrl.isNotEmpty
        ? Env.webBaseUrl
        : null;
    return _auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? webRedirect : kOAuthRedirectMobile,
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
  }

  @override
  Future<void> sendPasswordReset(String email, {String? redirectTo}) {
    return _auth.resetPasswordForEmail(email, redirectTo: redirectTo);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<Profile?> fetchProfile(String userId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return null;
    return Profile.fromJson(row);
  }

  @override
  Future<Profile> updateProfile({
    required String userId,
    String? displayName,
    String? bio,
    String? avatarUrl,
  }) async {
    final updates = <String, dynamic>{
      'display_name': ?displayName,
      'bio': ?bio,
      'avatar_url': ?avatarUrl,
    };
    final row = await _client
        .from('profiles')
        .update(updates)
        .eq('id', userId)
        .select()
        .single();
    return Profile.fromJson(row);
  }

  static const String _avatarsBucket = 'avatars';

  @override
  Future<String> uploadAvatar({
    required String userId,
    required List<int> bytes,
    required String fileExtension,
    required String contentType,
  }) async {
    // Chemin sous le dossier de l'utilisateur : requis par la RLS storage
    // (premier segment = auth.uid()).
    final path = '$userId/avatar.$fileExtension';
    await _client.storage
        .from(_avatarsBucket)
        .uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return path;
  }

  @override
  Future<String?> signedAvatarUrl(
    String? storagePath, {
    int expiresInSeconds = 3600,
  }) async {
    if (storagePath == null || storagePath.isEmpty) return null;
    return _client.storage
        .from(_avatarsBucket)
        .createSignedUrl(storagePath, expiresInSeconds);
  }
}
