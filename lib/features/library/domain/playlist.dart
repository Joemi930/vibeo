/// Playlist d'un utilisateur, miroir de la table `playlists`.
///
/// Privée par défaut : [isPublic] doit être activé explicitement. La RLS
/// applique la même règle, une playlist privée est invisible pour les autres.
class Playlist {
  const Playlist({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.createdAt,
    this.description,
    this.isPublic = false,
    this.itemCount = 0,
    this.updatedAt,
    this.coverPath,
  });

  final String id;
  final String ownerId;
  final String title;
  final String? description;
  final bool isPublic;

  /// Chemin (pas une URL) dans le bucket privé `playlist-covers`, convention
  /// `<uid>/<playlist_id>.<ext>`. `null` si aucune couverture n'a été choisie.
  final String? coverPath;

  /// Nombre de clips, maintenu par trigger SQL — jamais écrit par le client.
  final int itemCount;

  final DateTime createdAt;
  final DateTime? updatedAt;

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final ownerId = json['owner_id'];
    final title = json['title'];
    final createdAtRaw = json['created_at'];

    if (id is! String || id.isEmpty) {
      throw const FormatException('Playlist.fromJson : champ "id" invalide.');
    }
    if (ownerId is! String || ownerId.isEmpty) {
      throw const FormatException(
        'Playlist.fromJson : champ "owner_id" invalide.',
      );
    }
    if (title is! String || title.isEmpty) {
      throw const FormatException(
        'Playlist.fromJson : champ "title" invalide.',
      );
    }
    if (createdAtRaw is! String) {
      throw const FormatException(
        'Playlist.fromJson : champ "created_at" invalide.',
      );
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) {
      throw const FormatException(
        'Playlist.fromJson : "created_at" n\'est pas une date valide.',
      );
    }

    final updatedAtRaw = json['updated_at'];

    return Playlist(
      id: id,
      ownerId: ownerId,
      title: title,
      description: json['description'] as String?,
      isPublic: json['is_public'] as bool? ?? false,
      itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
      createdAt: createdAt,
      updatedAt: updatedAtRaw is String
          ? DateTime.tryParse(updatedAtRaw)
          : null,
      coverPath: json['cover_path'] as String?,
    );
  }

  /// Sérialise les champs que le client a le droit d'écrire.
  ///
  /// `item_count` est exclu : il vient d'un trigger (règle n°6 de CLAUDE.md).
  Map<String, dynamic> toJson() => {
    'owner_id': ownerId,
    'title': title,
    'description': description,
    'is_public': isPublic,
    'cover_path': coverPath,
  };

  Playlist copyWith({
    String? title,
    String? description,
    bool? isPublic,
    int? itemCount,
    String? coverPath,
    bool clearDescription = false,
    bool clearCover = false,
  }) => Playlist(
    id: id,
    ownerId: ownerId,
    title: title ?? this.title,
    description: clearDescription ? null : (description ?? this.description),
    isPublic: isPublic ?? this.isPublic,
    itemCount: itemCount ?? this.itemCount,
    createdAt: createdAt,
    updatedAt: updatedAt,
    coverPath: clearCover ? null : (coverPath ?? this.coverPath),
  );

  @override
  bool operator ==(Object other) =>
      other is Playlist &&
      other.id == id &&
      other.ownerId == ownerId &&
      other.title == title &&
      other.description == description &&
      other.isPublic == isPublic &&
      other.itemCount == itemCount &&
      other.createdAt == createdAt &&
      other.coverPath == coverPath;

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    title,
    description,
    isPublic,
    itemCount,
    createdAt,
    coverPath,
  );
}
