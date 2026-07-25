import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/genre_chip.dart';
import '../../../video/domain/genre.dart';
import '../../../video/presentation/providers/video_providers.dart';
import '../providers/search_providers.dart';

/// Rangée de filtres par genre, propre à l'onglet Clips (voir `Search.dc.html`).
class SearchGenreFilterRow extends ConsumerWidget {
  const SearchGenreFilterRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genresAsync = ref.watch(genresProvider);
    final selectedGenreId = ref.watch(
      searchQueryProvider.select((query) => query.genreId),
    );
    final notifier = ref.read(searchQueryProvider.notifier);

    final genres = genresAsync.asData?.value ?? const <Genre>[];
    if (genres.isEmpty) return const SizedBox(height: 12);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        children: [
          GenreChip(
            label: 'Tous',
            selected: selectedGenreId == null,
            onTap: () {
              if (selectedGenreId != null) {
                notifier.toggleGenre(selectedGenreId);
              }
            },
          ),
          for (final genre in genres) ...[
            const SizedBox(width: 8),
            GenreChip(
              label: genre.name,
              selected: selectedGenreId == genre.id,
              onTap: () => notifier.toggleGenre(genre.id),
            ),
          ],
        ],
      ),
    );
  }
}
