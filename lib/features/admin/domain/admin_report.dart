/// Nature de la cible d'un signalement.
enum ReportTargetKind {
  video('video'),
  comment('comment');

  const ReportTargetKind(this.value);
  final String value;

  static ReportTargetKind fromString(String? raw) {
    for (final kind in ReportTargetKind.values) {
      if (kind.value == raw) return kind;
    }
    return ReportTargetKind.video;
  }
}

/// Motif d'un signalement.
enum ReportReason {
  spam('spam', 'Indésirable'),
  hateSpeech('hate_speech', 'Discours haineux'),
  sexualContent('sexual_content', 'Contenu sexuel'),
  violence('violence', 'Violence'),
  copyright('copyright', 'Atteinte aux droits d\'auteur'),
  misinformation('misinformation', 'Désinformation'),
  other('other', 'Autre');

  const ReportReason(this.value, this.label);
  final String value;
  final String label;

  static ReportReason fromString(String? raw) {
    for (final reason in ReportReason.values) {
      if (reason.value == raw) return reason;
    }
    return ReportReason.other;
  }
}

/// Statut d'un signalement.
enum ReportStatus {
  pending('pending', 'En attente'),
  reviewed('reviewed', 'Traité'),
  dismissed('dismissed', 'Rejeté');

  const ReportStatus(this.value, this.label);
  final String value;
  final String label;

  static ReportStatus fromString(String? raw) {
    for (final status in ReportStatus.values) {
      if (status.value == raw) return status;
    }
    return ReportStatus.pending;
  }
}

/// Un signalement, tel que lu directement depuis la table `reports` (lecture
/// admin uniquement, RLS `reports_select_admin`).
class AdminReport {
  const AdminReport({
    required this.id,
    required this.reporterId,
    required this.targetKind,
    required this.reason,
    required this.status,
    required this.priority,
    required this.createdAt,
    this.videoId,
    this.commentId,
    this.targetAuthorId,
    this.details,
    this.reviewedAt,
    this.reviewedBy,
    this.reporterUsername,
    this.targetAuthorUsername,
    this.videoTitle,
    this.commentContent,
  });

  final String id;
  final String reporterId;
  final String? videoId;
  final String? commentId;
  final ReportTargetKind targetKind;
  final String? targetAuthorId;
  final ReportReason reason;
  final String? details;
  final ReportStatus status;
  final int priority;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  // Champs de contexte, résolus séparément (voir `AdminRepository`).
  final String? reporterUsername;
  final String? targetAuthorUsername;
  final String? videoTitle;
  final String? commentContent;

  factory AdminReport.fromJson(Map<String, dynamic> json) {
    return AdminReport(
      id: json['id'] as String,
      reporterId: json['reporter_id'] as String,
      videoId: json['video_id'] as String?,
      commentId: json['comment_id'] as String?,
      targetKind: ReportTargetKind.fromString(json['target_kind'] as String?),
      targetAuthorId: json['target_author_id'] as String?,
      reason: ReportReason.fromString(json['reason'] as String?),
      details: json['details'] as String?,
      status: ReportStatus.fromString(json['status'] as String?),
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      reviewedAt: json['reviewed_at'] == null
          ? null
          : DateTime.parse(json['reviewed_at'] as String),
      reviewedBy: json['reviewed_by'] as String?,
    );
  }

  AdminReport copyWithContext({
    String? reporterUsername,
    String? targetAuthorUsername,
    String? videoTitle,
    String? commentContent,
  }) {
    return AdminReport(
      id: id,
      reporterId: reporterId,
      videoId: videoId,
      commentId: commentId,
      targetKind: targetKind,
      targetAuthorId: targetAuthorId,
      reason: reason,
      details: details,
      status: status,
      priority: priority,
      createdAt: createdAt,
      reviewedAt: reviewedAt,
      reviewedBy: reviewedBy,
      reporterUsername: reporterUsername ?? this.reporterUsername,
      targetAuthorUsername: targetAuthorUsername ?? this.targetAuthorUsername,
      videoTitle: videoTitle ?? this.videoTitle,
      commentContent: commentContent ?? this.commentContent,
    );
  }
}
