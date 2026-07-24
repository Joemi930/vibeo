/// Rôle d'un utilisateur Vibeo, aligné sur l'enum SQL `user_role`.
enum UserRole {
  listener,
  artist,
  admin;

  /// Convertit la valeur texte de la base en [UserRole] (fallback [listener]).
  static UserRole fromString(String? value) {
    switch (value) {
      case 'artist':
        return UserRole.artist;
      case 'admin':
        return UserRole.admin;
      case 'listener':
      default:
        return UserRole.listener;
    }
  }

  /// Valeur texte attendue par la base.
  String get value => name;
}
