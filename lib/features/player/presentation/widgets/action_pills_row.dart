import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/share_links.dart';

import '../../../../core/auth/require_auth.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../social/presentation/providers/social_providers.dart';
import '../../../social/presentation/widgets/report_sheet.dart';
import '../../../video/domain/video.dart';
import '../providers/playback_providers.dart';

/// Rangée d'actions défilante horizontalement : like, commenter, partager,
/// passer en mode audio, signaler (voir `Maquettes/Player.dc.html`).
///
/// [onComment] fait défiler jusqu'au fil de commentaires puis y ouvre le
/// clavier — voir `CommentsSection.requestFocus`.
class ActionPillsRow extends ConsumerWidget {
  const ActionPillsRow({
    required this.video,
    required this.onComment,
    super.key,
  });

  final Video video;
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final likeState = ref.watch(likeControllerProvider(video.id));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Pill(
            icon: likeState.isLiked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            label: formatCompactCount(video.likeCount + likeState.delta),
            active: likeState.isLiked,
            semanticLabel: likeState.isLiked
                ? 'Retirer le like de ce clip'
                : 'Aimer ce clip',
            onTap: () => _toggleLike(context, ref),
          ),
          const SizedBox(width: 8),
          _Pill(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Commenter',
            semanticLabel: 'Commenter ce clip',
            onTap: () => _comment(context, ref),
          ),
          const SizedBox(width: 8),
          _Pill(
            icon: Icons.share_rounded,
            label: 'Partager',
            semanticLabel: 'Partager ce clip',
            onTap: () => _share(context),
          ),
          const SizedBox(width: 8),
          _Pill(
            icon: Icons.headphones_rounded,
            label: 'Audio',
            semanticLabel: 'Passer en mode audio',
            onTap: () => _goAudio(context, ref),
          ),
          const SizedBox(width: 8),
          _RoundIconButton(
            icon: Icons.flag_outlined,
            tooltip: 'Signaler',
            color: theme.colorScheme.onSurfaceVariant,
            onTap: () => _report(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleLike(BuildContext context, WidgetRef ref) async {
    if (!await requireAuth(context, ref, gate: AuthGate.like)) return;
    ref.read(likeControllerProvider(video.id).notifier).toggle();
  }

  Future<void> _comment(BuildContext context, WidgetRef ref) async {
    if (!await requireAuth(context, ref, gate: AuthGate.comment)) return;
    onComment();
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    if (!await requireAuth(context, ref, gate: AuthGate.report)) return;
    if (!context.mounted) return;
    await showReportSheet(context, videoId: video.id);
  }

  Future<void> _share(BuildContext context) async {
    // Le lien pointe vers `/#/video/<id>`, une route publique : le
    // destinataire ouvre le clip sans compte.
    final text = ShareLinks.videoMessage(
      videoId: video.id,
      title: video.title,
      artistName: video.artist?.resolvedName,
    );
    await SharePlus.instance.share(
      ShareParams(text: text, subject: video.title),
    );
  }

  Future<void> _goAudio(BuildContext context, WidgetRef ref) async {
    await ref.read(playbackControllerProvider.notifier).switchToAudio();
    if (!context.mounted) return;
    context.push('/audio');
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.semanticLabel,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String semanticLabel;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    return Semantics(
      button: true,
      toggled: active,
      label: semanticLabel,
      child: Material(
        color: active
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        icon: Icon(icon, size: 19, color: color),
      ),
    );
  }
}
