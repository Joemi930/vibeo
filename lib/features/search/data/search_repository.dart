import 'package:supabase_flutter/supabase_flutter.dart';

import '../../video/domain/artist_summary.dart';
import '../../video/domain/video.dart';
import '../../video/domain/video_status.dart';

/// Recherche de clips et d'artistes.
///
/// S'appuie sur les index trigram (`pg_trgm`) posés sur `videos.title`,
/// `profiles.username` et `profiles.display_name` : un `ilike '%...%'` reste
/// donc rapide malgré le joker en tête.
abstract class SearchRepository {
  /// Clips publiés dont le titre correspond, filtrés éventuellement par genre.
  Future<List<Video>> searchVideos(
    String query, {
    int? genreId,
    int limit = 30,
  });

  /// Artistes vérifiés dont le nom ou le pseudo correspond.
  Future<List<ArtistSummary>> searchArtists(String query, {int limit = 30});
}

class SupabaseSearchRepository implements SearchRepository {
  SupabaseSearchRepository(this._client);

  final SupabaseClient _client;

  /// En dessous de ce seuil, la recherche n'est pas lancée : trop de
  /// résultats, et l'index trigram perd tout intérêt.
  static const int minQueryLength = 2;

  static const String _selectWithArtist = '''
    *,
    artist:profiles!videos_artist_id_fkey (
      id, username, display_name, avatar_url, role, subscriber_count
    )
  ''';

  @override
  Future<List<Video>> searchVideos(
    String query, {
    int? genreId,
    int limit = 30,
  }) async {
    final term = _sanitize(query);
    if (term == null) return const [];

    var request = _client
        .from('videos')
        .select(_selectWithArtist)
        .eq('status', VideoStatus.published.value)
        .ilike('title', '%$term%');

    if (genreId != null) {
      request = request.eq('genre_id', genreId);
    }

    final rows = await request
        .order('published_at', ascending: false)
        .limit(limit);
    return rows.map<Video>(Video.fromJson).toList();
  }

  @override
  Future<List<ArtistSummary>> searchArtists(
    String query, {
    int limit = 30,
  }) async {
    final term = _sanitize(query);
    if (term == null) return const [];

    final rows = await _client
        .from('profiles')
        .select(
          'id, username, display_name, avatar_url, role, subscriber_count',
        )
        .eq('role', 'artist')
        .or('username.ilike.%$term%,display_name.ilike.%$term%')
        .order('subscriber_count', ascending: false)
        .limit(limit);

    return rows.map<ArtistSummary>(ArtistSummary.fromJson).toList();
  }

  /// Neutralise les jokers `%` et `_` d'un motif `ilike`.
  ///
  /// Sans cela, une recherche « % » listerait tout le catalogue. Ce n'est pas
  /// une injection SQL (PostgREST passe la valeur en paramètre), mais bien une
  /// injection de motif.
  static String? _sanitize(String query) {
    final trimmed = query.trim();
    if (trimmed.length < minQueryLength) return null;
    return trimmed
        .replaceAll('\\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_')
        .replaceAll(',', ' ');
  }
}
