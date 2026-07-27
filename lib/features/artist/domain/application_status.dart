/// Statut d'une candidature artiste.
///
/// Aligné sur l'enum SQL `public.application_status`. Copie le patron de
/// `lib/features/video/domain/video_status.dart` : un statut inconnu retombe
/// sur [pending] plutôt que de faire échouer tout le chargement.
enum ApplicationStatus {
  pending('pending', 'Envoyée'),
  manualReview('manual_review', 'En cours d\'analyse'),
  approved('approved', 'Approuvée'),
  rejected('rejected', 'Rejetée');

  const ApplicationStatus(this.value, this.label);

  /// Valeur telle que stockée en base.
  final String value;

  /// Libellé affiché à l'utilisateur.
  final String label;

  /// Un statut inconnu est traité comme [pending] plutôt que de faire
  /// échouer tout le chargement.
  static ApplicationStatus fromString(String? raw) {
    for (final status in ApplicationStatus.values) {
      if (status.value == raw) return status;
    }
    return ApplicationStatus.pending;
  }

  /// Vrai tant que la candidature est encore ouverte (envoyée ou en cours
  /// d'analyse) : c'est ce qui bloque une nouvelle candidature.
  bool get isOpen =>
      this == ApplicationStatus.pending ||
      this == ApplicationStatus.manualReview;

  bool get isApproved => this == ApplicationStatus.approved;

  bool get isRejected => this == ApplicationStatus.rejected;
}
