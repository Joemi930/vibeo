import 'artist_summary.dart';
import 'video_status.dart';

/// Clip vidéo, miroir de la table `videos`.
///
/// Les compteurs [viewCount], [likeCount] et [commentCount] sont en lecture
/// seule côté client : ils sont alimentés par des triggers SQL et ne sont
/// jamais sérialisés dans [toJson].
class Video {
  const Video({
    required this.id,
    required this.artistId,
    required this.title,
    required this.videoPath,
    required this.status,
    required this.createdAt,
    this.description,
    this.genreId,
    this.thumbnailPath,
    this.durationSeconds,
    this.sizeBytes,
    this.viewCount = 0,
    this.likeCount = 0,
    this.commentCount = 0,
    this.publishedAt,
    this.artist,
  });

  final String id;
  final String artistId;
  final String title;
  final String? description;
  final int? genreId;

  /// Chemin dans le bucket privé `videos` (pas une URL).
  final String videoPath;

  /// Chemin dans le bucket privé `thumbnails` (pas une URL).
  final String? thumbnailPath;

  final int? durationSeconds;
  final int? sizeBytes;
  final VideoStatus status;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final DateTime? publishedAt;
  final DateTime createdAt;

  /// Artiste joint à la requête, quand la sélection l'a demandé.
  final ArtistSummary? artist;

  Duration? get duration =>
      durationSeconds == null ? null : Duration(seconds: durationSeconds!);

  bool get isPublished => status.isPublished;

  /// Construit un [Video] depuis une ligne JSON de Supabase.
  ///
  /// Lève [FormatException] si les champs obligatoires (`id`, `artist_id`,
  /// `title`, `video_path`, `created_at`) sont absents ou d'un type invalide.
  factory Video.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final artistId = json['artist_id'];
    final title = json['title'];
    final videoPath = json['video_path'];
    final createdAtRaw = json['created_at'];

    if (id is! String || id.isEmpty) {
      throw const FormatException('Video.fromJson : champ "id" invalide.');
    }
    if (artistId is! String || artistId.isEmpty) {
      throw const FormatException(
        'Video.fromJson : champ "artist_id" invalide.',
      );
    }
    if (title is! String || title.isEmpty) {
      throw const FormatException('Video.fromJson : champ "title" invalide.');
    }
    if (videoPath is! String || videoPath.isEmpty) {
      throw const FormatException(
        'Video.fromJson : champ "video_path" invalide.',
      );
    }
    if (createdAtRaw is! String) {
      throw const FormatException(
        'Video.fromJson : champ "created_at" invalide.',
      );
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) {
      throw const FormatException(
        'Video.fromJson : "created_at" n\'est pas une date valide.',
      );
    }

    final publishedAtRaw = json['published_at'];

    // La jointure PostgREST peut renvoyer l'artiste sous `profiles` ou, si un
    // alias est utilisé, sous `artist`.
    final artistJson = (json['artist'] ?? json['profiles']);

    return Video(
      id: id,
      artistId: artistId,
      title: title,
      description: json['description'] as String?,
      genreId: (json['genre_id'] as num?)?.toInt(),
      videoPath: videoPath,
      thumbnailPath: json['thumbnail_path'] as String?,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      sizeBytes: (json['size_bytes'] as num?)?.toInt(),
      status: VideoStatus.fromString(json['status'] as String?),
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
      publishedAt: publishedAtRaw is String
          ? DateTime.tryParse(publishedAtRaw)
          : null,
      createdAt: createdAt,
      artist: artistJson is Map<String, dynamic>
          ? ArtistSummary.fromJson(artistJson)
          : null,
    );
  }

  /// Sérialise les champs que le client a le droit d'écrire.
  ///
  /// `view_count`, `like_count`, `comment_count` et `published_at` sont
  /// volontairement exclus :
  /// ils sont gérés par des triggers SQL (règle n°6 de CLAUDE.md) et toute
  /// tentative d'écriture serait de toute façon annulée côté base.
  Map<String, dynamic> toJson() => {
    'id': id,
    'artist_id': artistId,
    'title': title,
    'description': description,
    'genre_id': genreId,
    'video_path': videoPath,
    'thumbnail_path': thumbnailPath,
    'duration_seconds': durationSeconds,
    'size_bytes': sizeBytes,
    'status': status.value,
    'created_at': createdAt.toIso8601String(),
  };

  Video copyWith({
    String? title,
    String? description,
    int? genreId,
    String? thumbnailPath,
    VideoStatus? status,
    int? viewCount,
    int? likeCount,
    int? commentCount,
    DateTime? publishedAt,
    ArtistSummary? artist,
    // `null` signifie « ne touche pas » : ces drapeaux sont le seul moyen
    // d'exprimer « vide ce champ », par exemple quand l'artiste efface la
    // description ou retire le genre.
    bool clearDescription = false,
    bool clearGenre = false,
  }) {
    return Video(
      id: id,
      artistId: artistId,
      title: title ?? this.title,
      description: clearDescription ? null : (description ?? this.description),
      genreId: clearGenre ? null : (genreId ?? this.genreId),
      videoPath: videoPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      durationSeconds: durationSeconds,
      sizeBytes: sizeBytes,
      status: status ?? this.status,
      viewCount: viewCount ?? this.viewCount,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      publishedAt: publishedAt ?? this.publishedAt,
      createdAt: createdAt,
      artist: artist ?? this.artist,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Video &&
      other.id == id &&
      other.artistId == artistId &&
      other.title == title &&
      other.description == description &&
      other.genreId == genreId &&
      other.videoPath == videoPath &&
      other.thumbnailPath == thumbnailPath &&
      other.durationSeconds == durationSeconds &&
      other.sizeBytes == sizeBytes &&
      other.status == status &&
      other.viewCount == viewCount &&
      other.likeCount == likeCount &&
      other.commentCount == commentCount &&
      other.publishedAt == publishedAt &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    artistId,
    title,
    description,
    genreId,
    videoPath,
    thumbnailPath,
    durationSeconds,
    sizeBytes,
    status,
    viewCount,
    likeCount,
    commentCount,
    publishedAt,
    createdAt,
  );
}
