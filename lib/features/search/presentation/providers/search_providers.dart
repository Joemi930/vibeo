import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../video/domain/artist_summary.dart';
import '../../../video/domain/video.dart';
import '../../data/search_repository.dart';

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SupabaseSearchRepository(ref.watch(supabaseClientProvider));
});

/// Onglets de l'écran de recherche (`Maquettes/Search.dc.html`).
enum SearchTab { clips, artists }

@immutable
class SearchQuery {
  const SearchQuery({this.text = '', this.genreId});

  final String text;
  final int? genreId;

  bool get isActionable =>
      text.trim().length >= SupabaseSearchRepository.minQueryLength;

  SearchQuery copyWith({String? text, int? genreId, bool clearGenre = false}) =>
      SearchQuery(
        text: text ?? this.text,
        genreId: clearGenre ? null : (genreId ?? this.genreId),
      );

  @override
  bool operator ==(Object other) =>
      other is SearchQuery && other.text == text && other.genreId == genreId;

  @override
  int get hashCode => Object.hash(text, genreId);
}

/// Requête courante, mise à jour avec un délai d'attente.
///
/// Sans ce délai, chaque frappe déclencherait une requête réseau ; 300 ms est
/// le compromis habituel entre réactivité perçue et nombre d'appels.
class SearchQueryController extends Notifier<SearchQuery> {
  Timer? _debounce;

  @override
  SearchQuery build() {
    ref.onDispose(() => _debounce?.cancel());
    return const SearchQuery();
  }

  static const Duration debounceDelay = Duration(milliseconds: 300);

  void setText(String text) {
    _debounce?.cancel();
    _debounce = Timer(debounceDelay, () {
      state = state.copyWith(text: text);
    });
  }

  /// Applique immédiatement le texte (validation au clavier).
  void submit(String text) {
    _debounce?.cancel();
    state = state.copyWith(text: text);
  }

  void toggleGenre(int genreId) {
    state = state.genreId == genreId
        ? state.copyWith(clearGenre: true)
        : state.copyWith(genreId: genreId);
  }

  void clear() {
    _debounce?.cancel();
    state = const SearchQuery();
  }
}

final searchQueryProvider =
    NotifierProvider<SearchQueryController, SearchQuery>(
      SearchQueryController.new,
    );

/// Onglet sélectionné.
class SearchTabController extends Notifier<SearchTab> {
  @override
  SearchTab build() => SearchTab.clips;

  void select(SearchTab tab) => state = tab;
}

final searchTabProvider = NotifierProvider<SearchTabController, SearchTab>(
  SearchTabController.new,
);

/// Résultats « Clips ». Liste vide tant que la requête est trop courte.
final videoResultsProvider = FutureProvider<List<Video>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (!query.isActionable) return const [];
  return ref
      .watch(searchRepositoryProvider)
      .searchVideos(query.text, genreId: query.genreId);
});

/// Résultats « Artistes ». Le filtre par genre ne s'y applique pas.
final artistResultsProvider = FutureProvider<List<ArtistSummary>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (!query.isActionable) return const [];
  return ref.watch(searchRepositoryProvider).searchArtists(query.text);
});
