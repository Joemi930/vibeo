import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeo/features/auth/data/auth_repository.dart';
import 'package:vibeo/features/auth/domain/profile.dart';
import 'package:vibeo/features/auth/domain/user_role.dart';

/// Implémentation de test de [AuthRepository] : aucun appel réseau, comportement
/// configurable pour piloter les scénarios (succès, erreur d'auth, etc.).
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.throwOnSignIn,
    this.throwOnSignUp,
    User? initialUser,
  }) : _user = initialUser;

  /// Si non nul, [signIn] lève cette exception.
  final AuthException? throwOnSignIn;

  /// Si non nul, [signUp] lève cette exception.
  final AuthException? throwOnSignUp;

  final _controller = StreamController<AuthState>.broadcast();

  User? _user;
  Profile? profile;

  /// Simule une connexion/déconnexion sans passer par [signIn] : utile pour
  /// les tests qui n'ont besoin que d'un état « connecté » figé.
  void setUser(User? user) => _user = user;

  // Journal d'appels pour les assertions de test.
  final List<String> calls = [];

  @override
  Session? get currentSession => null;

  @override
  User? get currentUser => _user;

  @override
  Stream<AuthState> get onAuthStateChange => _controller.stream;

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
    String? emailRedirectTo,
  }) async {
    calls.add('signUp:$email:$username');
    if (throwOnSignUp != null) throw throwOnSignUp!;
    // Inscription avec confirmation email requise → pas de session.
    return AuthResponse(session: null, user: null);
  }

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    calls.add('signIn:$email');
    if (throwOnSignIn != null) throw throwOnSignIn!;
    return AuthResponse(session: null, user: null);
  }

  @override
  Future<bool> signInWithGoogle() async {
    calls.add('google');
    return true;
  }

  @override
  Future<void> sendPasswordReset(String email, {String? redirectTo}) async {
    calls.add('reset:$email');
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    _user = null;
  }

  @override
  Future<Profile?> fetchProfile(String userId) async => profile;

  @override
  Future<Profile> updateProfile({
    required String userId,
    String? displayName,
    String? bio,
    String? avatarUrl,
  }) async {
    calls.add('update:$userId');
    final base =
        profile ??
        Profile(
          id: userId,
          username: 'tester',
          role: UserRole.listener,
          createdAt: DateTime(2026, 1, 1),
        );
    profile = base.copyWith(
      displayName: displayName,
      bio: bio,
      avatarUrl: avatarUrl,
    );
    return profile!;
  }

  @override
  Future<String> uploadAvatar({
    required String userId,
    required List<int> bytes,
    required String fileExtension,
    required String contentType,
  }) async {
    calls.add('uploadAvatar:$userId');
    return '$userId/avatar.$fileExtension';
  }

  @override
  Future<String?> signedAvatarUrl(
    String? storagePath, {
    int expiresInSeconds = 3600,
  }) async {
    if (storagePath == null || storagePath.isEmpty) return null;
    return 'https://example.test/signed/$storagePath';
  }

  void dispose() => _controller.close();
}
