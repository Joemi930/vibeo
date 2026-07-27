import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/vibeo_app_bar.dart';
import 'providers/search_providers.dart';
import 'widgets/artist_results.dart';
import 'widgets/clip_results.dart';
import 'widgets/search_bar_field.dart';
import 'widgets/search_genre_filter_row.dart';
import 'widgets/search_tab_selector.dart';

/// Recherche de clips et d'artistes (voir `Maquettes/Search.dc.html`).
///
/// Publique : accessible sans compte, contrairement à la Bibliothèque.
class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(searchTabProvider);

    ref.listen(navigationPopSignalProvider, (_, _) {
      ref.invalidate(videoResultsProvider);
      ref.invalidate(artistResultsProvider);
    });

    return Scaffold(
      appBar: const VibeoAppBar(title: 'Recherche'),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SearchBarField(),
          ),
          // Le filtre par genre ne s'applique qu'aux clips : masqué sur
          // l'onglet Artistes plutôt que grisé, pour ne pas laisser un
          // contrôle inerte à l'écran.
          if (tab == SearchTab.clips) const SearchGenreFilterRow(),
          const SearchTabSelector(),
          Expanded(
            child: tab == SearchTab.clips
                ? const ClipResults()
                : const ArtistResults(),
          ),
        ],
      ),
    );
  }
}
