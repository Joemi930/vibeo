/// Origine d'une action de modération.
enum ModerationActor {
  ai('ai', 'IA'),
  admin('admin', 'Admin'),
  system('system', 'Système');

  const ModerationActor(this.value, this.label);
  final String value;
  final String label;

  static ModerationActor fromString(String? raw) {
    for (final actor in ModerationActor.values) {
      if (actor.value == raw) return actor;
    }
    return ModerationActor.system;
  }
}

/// Type de cible d'une ligne de journal.
enum ModerationTargetType {
  video('video', 'Clip'),
  comment('comment', 'Commentaire'),
  application('application', 'Candidature'),
  report('report', 'Signalement'),
  user('user', 'Utilisateur');

  const ModerationTargetType(this.value, this.label);
  final String value;
  final String label;

  static ModerationTargetType fromString(String? raw) {
    for (final type in ModerationTargetType.values) {
      if (type.value == raw) return type;
    }
    return ModerationTargetType.user;
  }
}

/// Une ligne du journal d'audit `moderation_logs` (lecture admin uniquement).
class ModerationLog {
  const ModerationLog({
    required this.id,
    required this.actor,
    required this.targetType,
    required this.action,
    required this.createdAt,
    this.actorId,
    this.targetId,
    this.reason,
    this.metadata,
  });

  final int id;
  final ModerationActor actor;
  final String? actorId;
  final ModerationTargetType targetType;
  final String? targetId;
  final String action;
  final String? reason;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  factory ModerationLog.fromJson(Map<String, dynamic> json) {
    return ModerationLog(
      id: (json['id'] as num).toInt(),
      actor: ModerationActor.fromString(json['actor'] as String?),
      actorId: json['actor_id'] as String?,
      targetType: ModerationTargetType.fromString(
        json['target_type'] as String?,
      ),
      targetId: json['target_id'] as String?,
      action: json['action'] as String? ?? '',
      reason: json['reason'] as String?,
      metadata: json['metadata'] is Map
          ? (json['metadata'] as Map).cast<String, dynamic>()
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
