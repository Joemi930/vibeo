/// Plafonds média, source de vérité unique côté client.
///
/// Ces valeurs doivent rester alignées sur les contraintes SQL et les limites
/// des buckets Storage (`supabase/migrations/20260725010100_videos.sql` et
/// `20260725010200_storage_videos.sql`) : le client vérifie pour donner un
/// message clair, le serveur reste seul juge.
///
/// Le plafond de 60 Mo est dicté par le tier gratuit Supabase (1 Go de
/// stockage) : il laisse la place à une quinzaine de clips de démonstration.
class MediaLimits {
  const MediaLimits._();

  /// Taille maximale d'un clip après compression.
  static const int maxVideoBytes = 60 * 1024 * 1024;

  /// Durée maximale d'un clip.
  static const Duration maxVideoDuration = Duration(minutes: 4);

  /// Taille maximale d'une miniature.
  static const int maxThumbnailBytes = 2 * 1024 * 1024;

  /// Taille maximale d'une couverture de playlist, alignée sur le plafond du
  /// bucket Storage `playlist-covers` (voir
  /// `supabase/migrations/20260726020000_phase35.sql`, section 4).
  static const int maxPlaylistCoverBytes = 5 * 1024 * 1024;

  /// Types MIME acceptés à l'upload d'un clip.
  static const List<String> videoMimeTypes = ['video/mp4', 'video/quicktime'];

  /// Extensions acceptées pour la sélection de fichier.
  static const List<String> videoExtensions = ['mp4', 'mov'];

  /// Types MIME acceptés pour une miniature.
  static const List<String> thumbnailMimeTypes = [
    'image/jpeg',
    'image/png',
    'image/webp',
  ];

  /// Durée de lecture minimale avant qu'une vue ne soit comptabilisée.
  /// Doit correspondre au seuil de la fonction SQL `public.record_view`.
  static const Duration viewCountThreshold = Duration(seconds: 10);

  /// Validité des URLs signées de lecture (vidéos et miniatures).
  static const int signedUrlTtlSeconds = 3600;

  /// Formate une taille en octets pour l'affichage (« 41,2 Mo »).
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} Ko';
    }
    final mo = bytes / (1024 * 1024);
    return '${mo.toStringAsFixed(1).replaceAll('.', ',')} Mo';
  }

  /// Formate une durée en `m:ss` (ou `h:mm:ss` au-delà de l'heure).
  static String formatDuration(Duration d) {
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      return '${d.inHours}:$minutes:$seconds';
    }
    return '${d.inMinutes}:$seconds';
  }
}
