import '../../artist/domain/application_status.dart';

/// Candidature d'artiste vue par l'administration (vue
/// `admin_artist_applications`).
///
/// N'expose JAMAIS le chemin du document d'identité : [hasDocument] le
/// remplace, l'admin obtient une URL signée à la demande via l'Edge Function
/// `admin-actions` (action `document_url`).
class AdminApplication {
  const AdminApplication({
    required this.id,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.stageName,
    required this.links,
    required this.statement,
    required this.hasDocument,
    required this.status,
    required this.createdAt,
    this.documentPurgedAt,
    this.aiScore,
    this.aiAnalysis,
    this.aiProvider,
    this.decisionReason,
    this.reviewedBy,
    this.decidedAt,
  });

  final String id;
  final String userId;
  final String username;
  final String? displayName;
  final String stageName;
  final List<String> links;
  final String statement;
  final bool hasDocument;
  final ApplicationStatus status;
  final DateTime createdAt;
  final DateTime? documentPurgedAt;
  final double? aiScore;
  final Map<String, dynamic>? aiAnalysis;
  final String? aiProvider;
  final String? decisionReason;
  final String? reviewedBy;
  final DateTime? decidedAt;

  /// Nom à afficher : nom de scène de préférence, sinon nom du profil.
  String get resolvedName => stageName.isNotEmpty
      ? stageName
      : (displayName?.isNotEmpty ?? false)
      ? displayName!
      : username;

  factory AdminApplication.fromJson(Map<String, dynamic> json) {
    return AdminApplication(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String?,
      stageName: json['stage_name'] as String? ?? '',
      links: (json['links'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      statement: json['statement'] as String? ?? '',
      hasDocument: json['has_document'] as bool? ?? false,
      status: ApplicationStatus.fromString(json['status'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
      documentPurgedAt: json['document_purged_at'] == null
          ? null
          : DateTime.parse(json['document_purged_at'] as String),
      aiScore: (json['ai_score'] as num?)?.toDouble(),
      aiAnalysis: json['ai_analysis'] is Map
          ? (json['ai_analysis'] as Map).cast<String, dynamic>()
          : null,
      aiProvider: json['ai_provider'] as String?,
      decisionReason: json['decision_reason'] as String?,
      reviewedBy: json['reviewed_by'] as String?,
      decidedAt: json['decided_at'] == null
          ? null
          : DateTime.parse(json['decided_at'] as String),
    );
  }
}
