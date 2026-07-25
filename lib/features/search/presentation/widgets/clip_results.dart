import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../core/widgets/video_card.dart';
import '../providers/search_providers.dart';
import 'search_states.dart';

/// Résultats de l'onglet Clips.
class ClipResults extends ConsumerWidget {
  const ClipResults({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider);

    if (!query.isActionable) {
      return const SearchInitialState(
        message: 'Recherche un titre, un artiste ou choisis un genre.',
      );
    }

    final resultsAsync = ref.watch(videoResultsProvider);
    return resultsAsync.when(
      loading: () => const RowListSkeleton(itemBuilder: _buildSkeletonRow),
      error: (_, _) => ErrorState(
        message: 'La recherche a échoué.',
        onRetry: () => ref.invalidate(videoResultsProvider),
      ),
      data: (videos) {
        if (videos.isEmpty) {
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
              itemCount: videos.length,
              itemBuilder: (context, index) {
                final video = videos[index];
                return VideoListTile(
                  video: video,
                  onTap: () => context.push(AppRoutes.video(video.id)),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

Widget _buildSkeletonRow(BuildContext context) => const VideoListTileSkeleton();
