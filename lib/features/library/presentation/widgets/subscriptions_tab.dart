import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/artist_list_tile.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../social/presentation/providers/social_providers.dart';

/// Onglet « Abonnements » de la Bibliothèque.
class SubscriptionsTab extends ConsumerWidget {
  const SubscriptionsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptionsAsync = ref.watch(subscriptionsProvider);

    return subscriptionsAsync.when(
      loading: () =>
          const RowListSkeleton(itemBuilder: _buildArtistSkeletonRow),
      error: (_, _) => ErrorState(
        message: 'Impossible de charger tes abonnements.',
        onRetry: () => ref.invalidate(subscriptionsProvider),
      ),
      data: (artists) {
        if (artists.isEmpty) {
          return EmptyState(
            icon: Icons.person_add_alt_1_outlined,
            title: 'Aucun abonnement',
            message:
                'Abonne-toi à tes artistes préférés pour retrouver leurs '
                'clips ici.',
            actionLabel: 'Découvrir des artistes',
            onAction: () => context.go(AppRoutes.search),
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

Widget _buildArtistSkeletonRow(BuildContext context) =>
    const ArtistRowSkeleton();
