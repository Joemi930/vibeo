import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/video_card.dart';
import '../../../video/domain/video.dart';
import '../../../video/presentation/providers/video_providers.dart';

/// Colonne « À suivre » du lecteur : clips suggérés après celui en cours.
///
/// Utilisée en colonne de droite sur écran large et sous les commentaires en
/// mobile (voir `player_screen.dart`). Réutilise [VideoListTile] telle quelle.
class SuggestionsColumn extends ConsumerWidget {
  const SuggestionsColumn({required this.videoId, super.key});

  final String videoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final suggestionsAsync = ref.watch(suggestedVideosProvider(videoId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'À suivre',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        suggestionsAsync.when(
          loading: () => const _SuggestionsLoading(),
          error: (_, _) => _SuggestionsError(
            onRetry: () => ref.invalidate(suggestedVideosProvider(videoId)),
          ),
          data: (videos) => videos.isEmpty
              ? const _SuggestionsEmpty()
              : _SuggestionsList(videos: videos),
        ),
      ],
    );
  }
}

class _SuggestionsList extends StatelessWidget {
  const _SuggestionsList({required this.videos});

  final List<Video> videos;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final video in videos)
          VideoListTile(
            video: video,
            onTap: () => context.push(AppRoutes.video(video.id)),
          ),
      ],
    );
  }
}

class _SuggestionsLoading extends StatelessWidget {
  const _SuggestionsLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class _SuggestionsEmpty extends StatelessWidget {
  const _SuggestionsEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        'Aucune suggestion pour le moment.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SuggestionsError extends StatelessWidget {
  const _SuggestionsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Impossible de charger les suggestions.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}
