/// Statistiques globales de la plateforme (vue `admin_stats`, une seule
/// ligne). Vue propriétaire côté base : `where public.is_admin()` est
/// l'unique barrière, ce modèle ne fait que refléter ce qu'elle renvoie.
class AdminStats {
  const AdminStats({
    required this.userCount,
    required this.artistCount,
    required this.publishedVideoCount,
    required this.moderationQueueCount,
    required this.applicationQueueCount,
    required this.openReportCount,
    required this.totalViewCount,
    required this.storageBytesUsed,
    required this.storageBytesLimit,
  });

  final int userCount;
  final int artistCount;
  final int publishedVideoCount;
  final int moderationQueueCount;
  final int applicationQueueCount;
  final int openReportCount;
  final int totalViewCount;
  final int storageBytesUsed;
  final int storageBytesLimit;

  /// Fraction d'occupation du stockage, entre 0 et 1.
  double get storageRatio =>
      storageBytesLimit <= 0 ? 0 : storageBytesUsed / storageBytesLimit;

  factory AdminStats.fromJson(Map<String, dynamic> json) {
    return AdminStats(
      userCount: (json['user_count'] as num?)?.toInt() ?? 0,
      artistCount: (json['artist_count'] as num?)?.toInt() ?? 0,
      publishedVideoCount:
          (json['published_video_count'] as num?)?.toInt() ?? 0,
      moderationQueueCount:
          (json['moderation_queue_count'] as num?)?.toInt() ?? 0,
      applicationQueueCount:
          (json['application_queue_count'] as num?)?.toInt() ?? 0,
      openReportCount: (json['open_report_count'] as num?)?.toInt() ?? 0,
      totalViewCount: (json['total_view_count'] as num?)?.toInt() ?? 0,
      storageBytesUsed: (json['storage_bytes_used'] as num?)?.toInt() ?? 0,
      storageBytesLimit:
          (json['storage_bytes_limit'] as num?)?.toInt() ?? 1073741824,
    );
  }
}
