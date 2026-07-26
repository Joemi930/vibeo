/// Identité civile d'un utilisateur (nom légal), miroir de la table privée
/// `public.user_identities`.
///
/// Volontairement séparée de [Profile] (auth/domain/profile.dart) : `profiles`
/// est lisible par tout le monde (y compris `anon`), alors que le nom civil ne
/// doit jamais être exposé publiquement — voir la migration
/// `20260726020000_phase35.sql` §1.
class LegalIdentity {
  const LegalIdentity({
    required this.userId,
    required this.legalFirstName,
    required this.legalLastName,
    this.legalMiddleName,
    this.updatedAt,
  });

  final String userId;
  final String legalFirstName;
  final String legalLastName;

  /// Post-nom (usage courant en RDC/Afrique centrale) : optionnel.
  final String? legalMiddleName;
  final DateTime? updatedAt;

  /// Construit une [LegalIdentity] depuis une ligne JSON de Supabase.
  ///
  /// Lève [FormatException] si les champs obligatoires (`user_id`,
  /// `legal_first_name`, `legal_last_name`) sont absents ou d'un type invalide.
  factory LegalIdentity.fromJson(Map<String, dynamic> json) {
    final userId = json['user_id'];
    final firstName = json['legal_first_name'];
    final lastName = json['legal_last_name'];

    if (userId is! String || userId.isEmpty) {
      throw const FormatException(
        'LegalIdentity.fromJson : champ "user_id" invalide.',
      );
    }
    if (firstName is! String || firstName.trim().isEmpty) {
      throw const FormatException(
        'LegalIdentity.fromJson : champ "legal_first_name" invalide.',
      );
    }
    if (lastName is! String || lastName.trim().isEmpty) {
      throw const FormatException(
        'LegalIdentity.fromJson : champ "legal_last_name" invalide.',
      );
    }

    DateTime? updatedAt;
    final updatedAtRaw = json['updated_at'];
    if (updatedAtRaw is String) {
      updatedAt = DateTime.tryParse(updatedAtRaw);
    }

    return LegalIdentity(
      userId: userId,
      legalFirstName: firstName,
      legalLastName: lastName,
      legalMiddleName: json['legal_middle_name'] as String?,
      updatedAt: updatedAt,
    );
  }

  /// Sérialise les champs modifiables par le client (upsert).
  ///
  /// `updated_at` est volontairement absent : il est posé automatiquement par
  /// `user_identities_guard_client_fields` côté base, jamais par le client.
  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'legal_first_name': legalFirstName,
    'legal_last_name': legalLastName,
    'legal_middle_name': legalMiddleName,
  };

  @override
  bool operator ==(Object other) =>
      other is LegalIdentity &&
      other.userId == userId &&
      other.legalFirstName == legalFirstName &&
      other.legalLastName == legalLastName &&
      other.legalMiddleName == legalMiddleName &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    userId,
    legalFirstName,
    legalLastName,
    legalMiddleName,
    updatedAt,
  );
}
