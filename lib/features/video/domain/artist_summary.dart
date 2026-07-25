import '../../auth/domain/user_role.dart';

/// Vue réduite d'un profil d'artiste, telle que jointe à une vidéo.
///
/// On n'utilise pas [Profile] ici : la jointure PostgREST ne ramène qu'un
/// sous-ensemble de colonnes (pas de `created_at`), ce qui ferait échouer
/// `Profile.fromJson`. Ce modèle porte exactement ce qu'affiche une carte de
/// clip : un nom, un avatar et l'insigne de vérification.
class ArtistSummary {
  const ArtistSummary({
    required this.id,
    required this.username,
    required this.role,
    this.displayName,
    this.avatarPath,
    this.subscriberCount = 0,
  });

  final String id;
  final String username;
  final String? displayName;

  /// Chemin dans le bucket privé `avatars` (pas une URL).
  final String? avatarPath;
  final UserRole role;
  final int subscriberCount;

  /// Nom à afficher (display_name si présent, sinon username).
  String get resolvedName =>
      (displayName != null && displayName!.trim().isNotEmpty)
      ? displayName!
      : username;

  /// Seuls les artistes portent l'insigne de vérification.
  bool get isVerified => role == UserRole.artist;

  /// Construit un [ArtistSummary] depuis la jointure `profiles` d'une vidéo.
  ///
  /// Lève [FormatException] si `id` ou `username` sont absents ou invalides.
  factory ArtistSummary.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final username = json['username'];
    if (id is! String || id.isEmpty) {
      throw const FormatException(
        'ArtistSummary.fromJson : champ "id" invalide.',
      );
    }
    if (username is! String || username.isEmpty) {
      throw const FormatException(
        'ArtistSummary.fromJson : champ "username" invalide.',
      );
    }
    return ArtistSummary(
      id: id,
      username: username,
      displayName: json['display_name'] as String?,
      avatarPath: json['avatar_url'] as String?,
      role: UserRole.fromString(json['role'] as String?),
      subscriberCount: (json['subscriber_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'display_name': displayName,
    'avatar_url': avatarPath,
    'role': role.value,
    'subscriber_count': subscriberCount,
  };

  @override
  bool operator ==(Object other) =>
      other is ArtistSummary &&
      other.id == id &&
      other.username == username &&
      other.displayName == displayName &&
      other.avatarPath == avatarPath &&
      other.role == role &&
      other.subscriberCount == subscriberCount;

  @override
  int get hashCode =>
      Object.hash(id, username, displayName, avatarPath, role, subscriberCount);
}
