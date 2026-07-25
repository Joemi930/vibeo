/// Motifs de signalement, miroir de l'enum SQL `public.report_reason`.
///
/// Les valeurs restent en anglais (convention du projet : identifiants en
/// anglais), seuls les libellés sont traduits.
enum ReportReason {
  spam('spam', 'Spam ou publicité'),
  hateSpeech('hate_speech', 'Propos haineux'),
  sexualContent('sexual_content', 'Contenu sexuel'),
  violence('violence', 'Violence'),
  copyright('copyright', 'Atteinte aux droits d\'auteur'),
  misinformation('misinformation', 'Fausse information'),
  other('other', 'Autre');

  const ReportReason(this.value, this.label);

  /// Valeur envoyée à la base.
  final String value;

  /// Libellé affiché dans la feuille de signalement.
  final String label;

  static ReportReason fromString(String? raw) {
    return ReportReason.values.firstWhere(
      (reason) => reason.value == raw,
      orElse: () => ReportReason.other,
    );
  }
}
