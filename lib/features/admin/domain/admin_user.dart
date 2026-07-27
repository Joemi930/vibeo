import '../../auth/domain/user_role.dart';

/// Utilisateur listé dans l'onglet « Utilisateurs » du dashboard admin.
class AdminUser {
  const AdminUser({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.bio,
    required this.role,
    required this.createdAt,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final UserRole role;
  final DateTime createdAt;

  String get resolvedName => displayName ?? username;

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String?,
      role: UserRole.fromString(json['role'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
