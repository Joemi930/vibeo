import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/media_limits.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../video/presentation/providers/video_providers.dart';
import '../providers/playback_providers.dart';

/// Lecteur réduit, ancré au-dessus de la barre de navigation.
///
/// Il ne détient aucun état : tout vient de [playbackControllerProvider], qui
/// vit à la racine de l'app. C'est pour cela que la lecture survit au
/// changement d'onglet et au retour depuis le lecteur plein écran.
///
/// Ne s'affiche que lorsqu'un clip est chargé.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackControllerProvider);
    final video = playback.video;
    if (video == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final controller = ref.read(playbackControllerProvider.notifier);
    final thumbnailUrl = ref
        .watch(thumbnailUrlProvider(video.thumbnailPath))
        .asData
        ?.value;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        elevation: 3,
        child: InkWell(
          onTap: () => context.push(AppRoutes.video(video.id)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
                child: Row(
                  children: [
                    _Thumbnail(url: thumbnailUrl),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            video.artist == null
                                ? video.title
                                : '${video.title} — ${video.artist!.resolvedName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${MediaLimits.formatDuration(playback.position)} / '
                            '${MediaLimits.formatDuration(playback.duration)}'
                            '${playback.isAudioMode ? ' · Audio' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: controller.togglePlay,
                      tooltip: playback.isPlaying ? 'Pause' : 'Lecture',
                      icon: Icon(
                        playback.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 26,
                      ),
                    ),
                    IconButton(
                      onPressed: controller.close,
                      tooltip: 'Fermer le lecteur',
                      icon: Icon(
                        Icons.close_rounded,
                        size: 22,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _ProgressBar(progress: playback.progress),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 40,
        height: 40,
        child: url == null
            ? Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.music_note_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Container(color: theme.colorScheme.surfaceContainerHighest),
              ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 2,
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            gradient: VibeoColors.of(context).gradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
