import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/theme/theme_mode_provider.dart';
import '../../data/video_repository.dart';
import '../../domain/genre.dart';
import '../../domain/video.dart';

/// Fournit le [VideoRepository] concret (surchargeable en test).
final videoRepositoryProvider = Provider<VideoRepository>((ref) {
  return SupabaseVideoRepository(ref.watch(supabaseClientProvider));
});

/// Genres musicaux (données de référence, rarement modifiées).
final genresProvider = FutureProvider<List<Genre>>((ref) {
  return ref.watch(videoRepositoryProvider).fetchGenres();
});

/// Genre sélectionné dans le filtre de l'accueil (null = tous les genres).
class SelectedGenreNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  /// Sélectionne un genre, ou le désélectionne s'il était déjà actif.
  void toggle(int genreId) => state = state == genreId ? null : genreId;

  void clear() => state = null;
}

final selectedGenreProvider = NotifierProvider<SelectedGenreNotifier, int?>(
  SelectedGenreNotifier.new,
);

/// Fil « Nouveautés » de l'accueil, filtré par le genre sélectionné.
final publishedVideosProvider = FutureProvider<List<Video>>((ref) {
  final genreId = ref.watch(selectedGenreProvider);
  return ref.watch(videoRepositoryProvider).fetchPublished(genreId: genreId);
});

/// Un clip par identifiant (lecteur, lien de partage).
final videoByIdProvider = FutureProvider.family<Video?, String>((ref, videoId) {
  return ref.watch(videoRepositoryProvider).fetchById(videoId);
});

/// Clips d'un artiste, pour sa page publique.
final artistVideosProvider = FutureProvider.family<List<Video>, String>((
  ref,
  artistId,
) {
  return ref.watch(videoRepositoryProvider).fetchByArtist(artistId);
});

/// Clips de l'artiste connecté, tous statuts confondus (Studio).
final studioVideosProvider = FutureProvider.family<List<Video>, String>((
  ref,
  artistId,
) {
  return ref
      .watch(videoRepositoryProvider)
      .fetchByArtist(artistId, onlyPublished: false);
});

/// URL signée d'une miniature (les buckets sont privés).
final thumbnailUrlProvider = FutureProvider.family<String?, String?>((
  ref,
  path,
) {
  return ref.watch(videoRepositoryProvider).signedThumbnailUrl(path);
});

/// URL signée du fichier vidéo, pour la lecture en streaming.
final videoUrlProvider = FutureProvider.family<String?, String?>((ref, path) {
  return ref.watch(videoRepositoryProvider).signedVideoUrl(path);
});

/// Clé de session opaque servant à dédupliquer les vues des invités.
///
/// Générée une fois puis conservée localement : elle ne contient aucune donnée
/// personnelle et sert uniquement d'anti-spam pour `record_view`, côté serveur.
final viewSessionKeyProvider = Provider<String>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  const key = 'view_session_key';
  final existing = prefs.getString(key);
  if (existing != null && existing.isNotEmpty) return existing;

  final random = Random.secure();
  final generated = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  // Écriture asynchrone volontairement non attendue : la valeur en mémoire est
  // déjà utilisable, la persistance n'est qu'un confort entre deux sessions.
  prefs.setString(key, generated);
  return generated;
});
