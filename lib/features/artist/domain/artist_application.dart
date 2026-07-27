import 'application_status.dart';

/// Candidature au statut artiste, telle que visible par le candidat lui-même.
///
/// Ne porte QUE les colonnes lisibles par le candidat (voir
/// `supabase/migrations/20260727010100_artist_applications.sql`, grants par
/// colonne) : `ai_score`, `ai_analysis`, `id_document_path` et `reviewed_by`
/// sont invisibles côté client et n'apparaissent donc jamais ici.
class ArtistApplication {
  const ArtistApplication({
    required this.id,
    required this.userId,
    required this.stageName,
    required this.links,
    required this.statement,
    required this.status,
    required this.createdAt,
    this.decisionReason,
    this.decidedAt,
    this.documentPurgedAt,
  });

  final String id;
  final String userId;
  final String stageName;
  final List<String> links;
  final String statement;
  final ApplicationStatus status;
  final DateTime createdAt;
  final String? decisionReason;
  final DateTime? decidedAt;
  final DateTime? documentPurgedAt;

  factory ArtistApplication.fromJson(Map<String, dynamic> json) {
    return ArtistApplication(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      stageName: json['stage_name'] as String,
      links: (json['links'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      statement: json['statement'] as String,
      status: ApplicationStatus.fromString(json['status'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
      decisionReason: json['decision_reason'] as String?,
      decidedAt: json['decided_at'] == null
          ? null
          : DateTime.parse(json['decided_at'] as String),
      documentPurgedAt: json['document_purged_at'] == null
          ? null
          : DateTime.parse(json['document_purged_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'stage_name': stageName,
      'links': links,
      'statement': statement,
      'status': status.value,
      'created_at': createdAt.toIso8601String(),
      'decision_reason': decisionReason,
      'decided_at': decidedAt?.toIso8601String(),
      'document_purged_at': documentPurgedAt?.toIso8601String(),
    };
  }
}
