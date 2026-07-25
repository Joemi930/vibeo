import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/format_utils.dart';
import '../../video/domain/video.dart';
import '../../video/presentation/providers/video_providers.dart';
import 'providers/playback_providers.dart';
import 'widgets/action_pills_row.dart';
import 'widgets/artist_row.dart';
import 'widgets/comments_section.dart';
import 'widgets/description_card.dart';
import 'widgets/player_skeleton.dart';
import 'widgets/video_surface.dart';

/// Lecteur plein écran d'un clip (voir `Maquettes/Player.dc.html` et
/// `Maquettes/WebPlayer.dc.html`).
///
/// Sans [AppBar] : la flèche de retour est posée directement sur la vidéo
/// (voir [VideoSurface]). Charge le clip demandé puis confie la lecture au
/// [playbackControllerProvider], qui survit à la navigation (mini-player).
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({required this.videoId, super.key});

  final String videoId;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  /// Identifiant du dernier clip transmis au lecteur, pour n'appeler `open`
  /// qu'une seule fois par clip (et pas à chaque reconstruction du widget).
  String? _openedVideoId;

  /// Permet à la pilule « Commenter » de faire défiler jusqu'au fil de
  /// commentaires puis d'y ouvrir le clavier, quelle que soit la mise en page
  /// (mobile ou colonne web) — un seul des deux est monté à la fois.
  final GlobalKey<CommentsSectionState> _commentsKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final videoAsync = ref.watch(videoByIdProvider(widget.videoId));

    // `ref.listen` ne réagit qu'aux changements futurs : on couvre en plus le
    // cas où la vidéo est déjà en cache dès ce premier rendu en regardant
    // directement la valeur courante ci-dessous.
    ref.listen<AsyncValue<Video?>>(
      videoByIdProvider(widget.videoId),
      (previous, next) => _openIfNeeded(next.value),
    );
    _openIfNeeded(videoAsync.value);

    return Scaffold(
      body: SafeArea(
        top: false,
        child: videoAsync.when(
          loading: () => const PlayerSkeleton(),
          error: (_, _) => _PlayerErrorState(
            onRetry: () => ref.invalidate(videoByIdProvider(widget.videoId)),
          ),
          data: (video) => video == null
              ? const _PlayerEmptyState()
              : _PlayerBody(video, commentsKey: _commentsKey),
        ),
      ),
    );
  }

  /// Ouvre [video] dans le lecteur si ce n'est pas déjà celui en cours.
  ///
  /// Le report en microtâche évite de modifier un autre provider pendant la
  /// construction de cet écran.
  void _openIfNeeded(Video? video) {
    if (video == null || _openedVideoId == video.id) return;
    _openedVideoId = video.id;
    Future.microtask(() {
      if (!mounted) return;
      ref.read(playbackControllerProvider.notifier).open(video);
    });
  }
}

/// Bascule entre la mise en page mobile (une colonne) et web (deux colonnes)
/// au-delà de 900 px de large (`Maquettes/WebPlayer.dc.html`).
class _PlayerBody extends StatelessWidget {
  const _PlayerBody(this.video, {required this.commentsKey});

  final Video video;
  final GlobalKey<CommentsSectionState> commentsKey;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        VideoSurface(video: video, borderRadius: 16),
                        _InfoColumn(
                          video: video,
                          showComments: false,
                          commentsKey: commentsKey,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 400,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: CommentsSection(key: commentsKey, videoId: video.id),
                  ),
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            VideoSurface(video: video),
            Expanded(
              child: SingleChildScrollView(
                child: _InfoColumn(
                  video: video,
                  showComments: true,
                  commentsKey: commentsKey,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InfoColumn extends StatelessWidget {
  const _InfoColumn({
    required this.video,
    required this.showComments,
    required this.commentsKey,
  });

  final Video video;
  final bool showComments;
  final GlobalKey<CommentsSectionState> commentsKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = video.description?.trim();
    final meta =
        '${formatGroupedCount(video.viewCount)} vues · '
        '${relativeDate(video.publishedAt ?? video.createdAt)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            video.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            meta,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          ArtistSubscribeRow(video: video),
          const SizedBox(height: 14),
          ActionPillsRow(
            video: video,
            onComment: () => commentsKey.currentState?.requestFocus(),
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 16),
            DescriptionCard(text: description),
          ],
          if (showComments) ...[
            const SizedBox(height: 20),
            CommentsSection(key: commentsKey, videoId: video.id),
          ],
        ],
      ),
    );
  }
}

class _PlayerEmptyState extends StatelessWidget {
  const _PlayerEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_off_outlined,
              size: 42,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              'Ce clip est introuvable.',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Il a peut-être été retiré ou déplacé.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => context.go('/'),
              child: const Text("Retour à l'accueil"),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerErrorState extends StatelessWidget {
  const _PlayerErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 14),
            Text(
              'Impossible de charger ce clip.',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Vérifie ta connexion et réessaie.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
