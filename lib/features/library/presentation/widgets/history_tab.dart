import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../core/widgets/video_card.dart';
import '../providers/library_providers.dart';

/// Onglet « Historique » de la Bibliothèque.
class HistoryTab extends ConsumerWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(watchHistoryProvider);

    return historyAsync.when(
      loading: () => const RowListSkeleton(itemBuilder: _buildVideoSkeletonRow),
      error: (_, _) => ErrorState(
        message: 'Impossible de charger ton historique.',
        onRetry: () => ref.invalidate(watchHistoryProvider),
      ),
      data: (videos) {
        if (videos.isEmpty) {
          return const EmptyState(
            icon: Icons.history_rounded,
            title: 'Aucun historique de lecture',
            message:
                'Les clips que tu regardes apparaîtront ici, du plus récent '
                'au plus ancien.',
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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

Widget _buildVideoSkeletonRow(BuildContext context) =>
    const VideoListTileSkeleton();
