import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/artist_list_tile.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../providers/search_providers.dart';
import 'search_states.dart';

/// Résultats de l'onglet Artistes.
class ArtistResults extends ConsumerWidget {
  const ArtistResults({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider);

    if (!query.isActionable) {
      return const SearchInitialState(
        message: 'Recherche le nom ou le pseudo d\'un artiste.',
      );
    }

    final resultsAsync = ref.watch(artistResultsProvider);
    return resultsAsync.when(
      loading: () => const RowListSkeleton(itemBuilder: _buildSkeletonRow),
      error: (_, _) => ErrorState(
        message: 'La recherche a échoué.',
        onRetry: () => ref.invalidate(artistResultsProvider),
      ),
      data: (artists) {
        if (artists.isEmpty) {
          return SearchNoResultsState(
            query: query.text.trim(),
            onClear: () => ref.read(searchQueryProvider.notifier).clear(),
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: artists.length,
              itemBuilder: (context, index) {
                final artist = artists[index];
                return ArtistListTile(
                  artist: artist,
                  onTap: () => context.push(AppRoutes.artist(artist.id)),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

Widget _buildSkeletonRow(BuildContext context) => const ArtistRowSkeleton();
