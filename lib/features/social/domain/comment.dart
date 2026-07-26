import '../../video/domain/artist_summary.dart';

/// Commentaire sur un clip, miroir de la table `comments`.
///
/// L'auteur est joint via `profiles` : on réutilise [ArtistSummary], qui porte
/// déjà le nom d'affichage, l'avatar et le badge vérifié.
class Comment {
  const Comment({
    required this.id,
    required this.videoId,
    required this.authorId,
    required this.body,
    required this.createdAt,
    this.updatedAt,
    this.author,
    this.parentId,
    this.replies = const [],
  });

  final String id;
  final String videoId;
  final String authorId;
  final String body;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Auteur joint à la requête, quand la sélection l'a demandé.
  final ArtistSummary? author;

  /// Commentaire parent, si celui-ci est une réponse. `null` pour un
  /// commentaire racine. Un seul niveau de profondeur est garanti par le
  /// serveur (trigger `comments_guard_client_fields`, voir la migration
  /// `20260726020000_phase35.sql`) : une réponse a donc toujours
  /// `parentId.replies` vide, jamais rempli par le client.
  final String? parentId;

  /// Réponses attachées à ce commentaire (uniquement pertinent pour un
  /// commentaire racine). Jamais lu depuis le JSON directement : rattaché en
  /// Dart par le repository après une requête séparée
  /// (voir `SupabaseSocialRepository.fetchComments`).
  final List<Comment> replies;

  /// Vrai si ce commentaire est lui-même une réponse.
  bool get isReply => parentId != null;

  /// Vrai si le commentaire a été retouché après sa publication.
  bool get isEdited =>
      updatedAt != null && updatedAt!.difference(createdAt).inSeconds > 1;

  /// Construit un [Comment] depuis une ligne JSON de Supabase.
  ///
  /// Lève [FormatException] si un champ obligatoire est absent ou invalide.
  factory Comment.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final videoId = json['video_id'];
    final authorId = json['author_id'];
    final body = json['body'];
    final createdAtRaw = json['created_at'];

    if (id is! String || id.isEmpty) {
      throw const FormatException('Comment.fromJson : champ "id" invalide.');
    }
    if (videoId is! String || videoId.isEmpty) {
      throw const FormatException(
        'Comment.fromJson : champ "video_id" invalide.',
      );
    }
    if (authorId is! String || authorId.isEmpty) {
      throw const FormatException(
        'Comment.fromJson : champ "author_id" invalide.',
      );
    }
    if (body is! String || body.isEmpty) {
      throw const FormatException('Comment.fromJson : champ "body" invalide.');
    }
    if (createdAtRaw is! String) {
      throw const FormatException(
        'Comment.fromJson : champ "created_at" invalide.',
      );
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) {
      throw const FormatException(
        'Comment.fromJson : "created_at" n\'est pas une date valide.',
      );
    }

    final updatedAtRaw = json['updated_at'];
    final authorJson = json['author'] ?? json['profiles'];
    final parentIdRaw = json['parent_id'];

    return Comment(
      id: id,
      videoId: videoId,
      authorId: authorId,
      body: body,
      createdAt: createdAt,
      updatedAt: updatedAtRaw is String
          ? DateTime.tryParse(updatedAtRaw)
          : null,
      author: authorJson is Map<String, dynamic>
          ? ArtistSummary.fromJson(authorJson)
          : null,
      parentId: parentIdRaw is String ? parentIdRaw : null,
    );
  }

  /// Sérialise les champs que le client a le droit d'écrire.
  ///
  /// `created_at`, `updated_at` et `deleted_at` sont posés par la base : un
  /// trigger les restaure de toute façon si le client tente de les fournir.
  /// `parent_id` n'est inclus que pour une réponse (création) : il est ensuite
  /// figé par le serveur, jamais réémis à une mise à jour.
  Map<String, dynamic> toJson() => {
    'video_id': videoId,
    'author_id': authorId,
    'body': body,
    if (parentId != null) 'parent_id': parentId,
  };

  Comment copyWith({
    String? body,
    DateTime? updatedAt,
    List<Comment>? replies,
  }) => Comment(
    id: id,
    videoId: videoId,
    authorId: authorId,
    body: body ?? this.body,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    author: author,
    parentId: parentId,
    replies: replies ?? this.replies,
  );

  @override
  bool operator ==(Object other) =>
      other is Comment &&
      other.id == id &&
      other.videoId == videoId &&
      other.authorId == authorId &&
      other.body == body &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.parentId == parentId;

  @override
  int get hashCode =>
      Object.hash(id, videoId, authorId, body, createdAt, updatedAt, parentId);
}
