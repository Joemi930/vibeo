import '../../video/domain/video_status.dart';

/// Clip en attente d'une action admin (vue `admin_video_queue`) :
/// traitement, modération ou déjà rejeté.
class AdminVideoQueueItem {
  const AdminVideoQueueItem({
    required this.id,
    required this.artistId,
    required this.artistUsername,
    required this.artistDisplayName,
    required this.title,
    required this.status,
    required this.createdAt,
    this.description,
    this.moderationResult,
    this.videoPath,
    this.thumbnailPath,
  });

  final String id;
  final String artistId;
  final String artistUsername;
  final String? artistDisplayName;
  final String title;
  final String? description;
  final VideoStatus status;
  final Map<String, dynamic>? moderationResult;
  final String? videoPath;
  final String? thumbnailPath;
  final DateTime createdAt;

  String get resolvedArtistName => (artistDisplayName?.isNotEmpty ?? false)
      ? artistDisplayName!
      : artistUsername;

  /// Motif technique renvoyé par la modération IA ou un admin précédent.
  String? get moderationReason => moderationResult?['reason'] as String?;

  factory AdminVideoQueueItem.fromJson(Map<String, dynamic> json) {
    return AdminVideoQueueItem(
      id: json['id'] as String,
      artistId: json['artist_id'] as String,
      artistUsername: json['artist_username'] as String? ?? '',
      artistDisplayName: json['artist_display_name'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      status: VideoStatus.fromString(json['status'] as String?),
      moderationResult: json['moderation_result'] is Map
          ? (json['moderation_result'] as Map).cast<String, dynamic>()
          : null,
      videoPath: json['video_path'] as String?,
      thumbnailPath: json['thumbnail_path'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
