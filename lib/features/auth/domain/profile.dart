import 'user_role.dart';

/// Profil public d'un utilisateur, miroir de la table `profiles`.
class Profile {
  const Profile({
    required this.id,
    required this.username,
    required this.role,
    required this.createdAt,
    this.displayName,
    this.avatarUrl,
    this.bio,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final UserRole role;
  final DateTime createdAt;

  /// Nom à afficher (display_name si présent, sinon username).
  String get resolvedName =>
      (displayName != null && displayName!.trim().isNotEmpty)
      ? displayName!
      : username;

  bool get isArtist => role == UserRole.artist;
  bool get isAdmin => role == UserRole.admin;

  /// Construit un [Profile] depuis une ligne JSON de Supabase.
  ///
  /// Lève [FormatException] si les champs obligatoires (`id`, `username`,
  /// `created_at`) sont absents ou d'un type invalide.
  factory Profile.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final username = json['username'];
    final createdAtRaw = json['created_at'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Profile.fromJson : champ "id" invalide.');
    }
    if (username is! String || username.isEmpty) {
      throw const FormatException(
        'Profile.fromJson : champ "username" invalide.',
      );
    }
    if (createdAtRaw is! String) {
      throw const FormatException(
        'Profile.fromJson : champ "created_at" invalide.',
      );
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) {
      throw const FormatException(
        'Profile.fromJson : "created_at" n\'est pas une date valide.',
      );
    }
    return Profile(
      id: id,
      username: username,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String?,
      role: UserRole.fromString(json['role'] as String?),
      createdAt: createdAt,
    );
  }

  /// Sérialise le profil (champs modifiables par le client).
  ///
  /// Le champ `role` n'est volontairement PAS inclus : il ne peut être modifié
  /// par le client (protégé par RLS + trigger côté base).
  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'bio': bio,
    'created_at': createdAt.toIso8601String(),
  };

  Profile copyWith({
    String? username,
    String? displayName,
    String? avatarUrl,
    String? bio,
    UserRole? role,
  }) {
    return Profile(
      id: id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      role: role ?? this.role,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Profile &&
      other.id == id &&
      other.username == username &&
      other.displayName == displayName &&
      other.avatarUrl == avatarUrl &&
      other.bio == bio &&
      other.role == role &&
      other.createdAt == createdAt;

  @override
  int get hashCode =>
      Object.hash(id, username, displayName, avatarUrl, bio, role, createdAt);
}
