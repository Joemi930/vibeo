/// Chemins de navigation centralisés (go_router).
///
/// Les écrans listés couvrent la maquette d'ARCHITECTURE §7. En Phase 1, seuls
/// Auth / Accueil / Recherche / Bibliothèque / Profil / Paramètres sont réels ;
/// les autres sont des squelettes navigables.
class AppRoutes {
  const AppRoutes._();

  // Authentification (hors shell).
  static const String auth = '/auth';
  static const String emailVerification = '/auth/verification';

  // Onglets principaux (dans le shell à barre de navigation).
  static const String home = '/';
  static const String search = '/search';
  static const String library = '/library';
  static const String profile = '/profile';

  // Écrans secondaires (squelettes en P1).
  static const String settings = '/settings';
  static const String player = '/player';
  static const String artist = '/artist';
  static const String becomeArtist = '/become-artist';
  static const String applicationStatus = '/application-status';
  static const String studio = '/studio';
  static const String upload = '/upload';
  static const String admin = '/admin';
}
