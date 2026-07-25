import 'package:vibeo/features/search/data/search_repository.dart';
import 'package:vibeo/features/video/domain/artist_summary.dart';
import 'package:vibeo/features/video/domain/video.dart';

/// Faux dépôt de recherche, écrit à la main. Filtre en mémoire par titre /
/// nom, sans jamais toucher au réseau.
class FakeSearchRepository implements SearchRepository {
  FakeSearchRepository({
    List<Video> videos = const [],
    List<ArtistSummary> artists = const [],
    this.throwOnSearch = false,
  }) : videos = [...videos],
       artists = [...artists];

  List<Video> videos;
  List<ArtistSummary> artists;
  bool throwOnSearch;

  final List<String> calls = [];

  @override
  Future<List<Video>> searchVideos(
    String query, {
    int? genreId,
    int limit = 30,
  }) async {
    calls.add('searchVideos:$query:$genreId');
    if (throwOnSearch) throw Exception('échec réseau simulé');
    final term = query.trim().toLowerCase();
    return videos
        .where(
          (v) =>
              v.title.toLowerCase().contains(term) &&
              (genreId == null || v.genreId == genreId),
        )
        .toList();
  }

  @override
  Future<List<ArtistSummary>> searchArtists(
    String query, {
    int limit = 30,
  }) async {
    calls.add('searchArtists:$query');
    if (throwOnSearch) throw Exception('échec réseau simulé');
    final term = query.trim().toLowerCase();
    return artists
        .where((a) => a.resolvedName.toLowerCase().contains(term))
        .toList();
  }
}
