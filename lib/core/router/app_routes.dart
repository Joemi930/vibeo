/// Chemins de navigation centralisés (go_router).
///
/// Les écrans listés couvrent la maquette d'ARCHITECTURE §7. En Phase 2, le
/// lecteur, l'upload et le studio deviennent réels ; la page artiste arrive en
/// Phase 3 ; candidature et administration restent des squelettes.
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

  // Écrans secondaires.
  static const String audio = '/audio';
  static const String settings = '/settings';
  static const String studio = '/studio';
  static const String upload = '/upload';
  static const String becomeArtist = '/become-artist';
  static const String applicationStatus = '/application-status';
  static const String admin = '/admin';

  // Écrans paramétrés. Les motifs `:id` servent à go_router, les fonctions
  // ci-dessous à construire un lien concret (partage, navigation interne).
  static const String videoPattern = '/video/:videoId';
  static const String artistPattern = '/artist/:artistId';
  static const String editVideoPattern = '/studio/video/:videoId/edit';

  /// Détail d'une playlist. Sous-route de la Bibliothèque : elle reste donc
  /// dans le shell, ce qui préserve la barre de navigation et le mini-player.
  static const String playlistSubPath = 'playlist/:playlistId';
  static String playlist(String playlistId) => '/library/playlist/$playlistId';

  /// Lecteur d'un clip — c'est aussi la cible des liens de partage.
  static String video(String videoId) => '/video/$videoId';

  /// Modification d'un clip par son artiste (réservée au Studio).
  static String editVideo(String videoId) => '/studio/video/$videoId/edit';

  /// Page publique d'un artiste.
  static String artist(String artistId) => '/artist/$artistId';

  /// Routes consultables sans compte (mode invité).
  ///
  /// Tout le reste exige une session : la garde du router y renvoie vers
  /// l'écran de connexion en mémorisant la destination d'origine.
  static bool isPublic(String location) {
    return location == home ||
        location == search ||
        location == audio ||
        location.startsWith('/video/') ||
        location.startsWith('/artist/');
  }

  /// Valide une destination `returnTo` avant de naviguer dessus.
  ///
  /// Sans ce filtre, un lien de hameçonnage
  /// (`/auth?returnTo=https://exemple-malveillant/`) enverrait l'utilisateur
  /// hors de l'app juste après avoir saisi ses identifiants — une
  /// **redirection ouverte**. Toute cible qui n'est pas un chemin interne
  /// simple retombe sur l'accueil.
  ///
  /// C'est l'unique point de confiance : tous les chemins de code qui
  /// exploitent `returnTo` doivent passer par ici.
  static String sanitizeReturnTo(String? raw) {
    if (raw == null || raw.isEmpty) return home;

    // Les antislashs sont normalisés en slashs par certains navigateurs :
    // `/\exemple.com` deviendrait `//exemple.com`, soit une URL
    // protocole-relative pointant vers un autre domaine.
    if (raw.contains(r'\')) return home;

    if (!raw.startsWith('/') || raw.startsWith('//')) return home;

    final uri = Uri.tryParse(raw);
    if (uri == null || uri.hasScheme || uri.hasAuthority) return home;

    // Revenir sur l'écran d'auth après connexion n'aurait aucun sens.
    if (raw == auth || raw.startsWith('$auth/') || raw.startsWith('$auth?')) {
      return home;
    }

    return raw;
  }
}
