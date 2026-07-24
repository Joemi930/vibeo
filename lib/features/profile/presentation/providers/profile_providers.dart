import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/domain/profile.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// Profil de l'utilisateur connecté (null si déconnecté ou introuvable).
final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final repo = ref.watch(authRepositoryProvider);
  return repo.fetchProfile(user.id);
});

/// Résout une URL signée temporaire pour un chemin d'avatar du bucket privé.
final avatarSignedUrlProvider = FutureProvider.family<String?, String?>((
  ref,
  path,
) async {
  if (path == null || path.isEmpty) return null;
  final repo = ref.watch(authRepositoryProvider);
  return repo.signedAvatarUrl(path);
});

/// Contrôleur d'édition du profil (enregistrement + avatar).
class ProfileController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Enregistre les champs modifiables et rafraîchit le profil.
  Future<bool> save({
    required String userId,
    String? displayName,
    String? bio,
  }) async {
    state = const AsyncLoading();
    try {
      await ref
          .read(authRepositoryProvider)
          .updateProfile(userId: userId, displayName: displayName, bio: bio);
      ref.invalidate(currentProfileProvider);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(_message(e), st);
      return false;
    }
  }

  /// Téléverse un nouvel avatar puis met à jour le profil.
  Future<bool> uploadAvatar({
    required String userId,
    required List<int> bytes,
    required String fileExtension,
    required String contentType,
  }) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(authRepositoryProvider);
      final path = await repo.uploadAvatar(
        userId: userId,
        bytes: bytes,
        fileExtension: fileExtension,
        contentType: contentType,
      );
      await repo.updateProfile(userId: userId, avatarUrl: path);
      ref.invalidate(currentProfileProvider);
      ref.invalidate(avatarSignedUrlProvider);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(_message(e), st);
      return false;
    }
  }

  static String _message(Object e) =>
      'Échec de l\'enregistrement. Réessaie dans un instant.';
}

final profileControllerProvider =
    AsyncNotifierProvider<ProfileController, void>(ProfileController.new);
