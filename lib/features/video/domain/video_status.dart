/// Statut de modération d'un clip.
///
/// Aligné sur l'enum SQL `public.video_status`. En Phase 2, un clip passe
/// directement de [processing] à [published] ; [pendingModeration] et
/// [rejected] entrent en jeu avec la modération IA (Phase 4).
enum VideoStatus {
  processing('processing', 'En traitement'),
  pendingModeration('pending_moderation', 'En modération'),
  published('published', 'Publié'),
  rejected('rejected', 'Rejeté'),
  removed('removed', 'Retiré');

  const VideoStatus(this.value, this.label);

  /// Valeur telle que stockée en base.
  final String value;

  /// Libellé affiché à l'utilisateur.
  final String label;

  /// Un statut inconnu est traité comme [processing] plutôt que de faire
  /// échouer tout le chargement d'une liste.
  static VideoStatus fromString(String? raw) {
    for (final status in VideoStatus.values) {
      if (status.value == raw) return status;
    }
    return VideoStatus.processing;
  }

  bool get isPublished => this == VideoStatus.published;
}
