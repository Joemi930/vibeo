import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/auth/require_auth.dart';
import '../../../video/domain/video.dart';
import '../providers/playback_providers.dart';
import '../../../../core/utils/format_utils.dart';

/// Rangée d'actions défilante horizontalement : like, commenter, partager,
/// passer en mode audio, signaler (voir `Maquettes/Player.dc.html`).
///
/// Seuls le partage et le passage en mode audio sont pleinement fonctionnels
/// en Phase 2 ; les autres ouvrent la garde d'authentification puis annoncent
/// la Phase 3, sans jamais fabriquer de compteur ou d'état qui n'existe pas
/// côté serveur.
class ActionPillsRow extends ConsumerWidget {
  const ActionPillsRow({required this.video, super.key});

  final Video video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Pill(
            icon: Icons.favorite_border_rounded,
            label: formatCompactCount(video.likeCount),
            onTap: () => _phase3(context, ref, AuthGate.like, 'Les likes'),
          ),
          const SizedBox(width: 8),
          _Pill(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Commenter',
            onTap: () =>
                _phase3(context, ref, AuthGate.comment, 'Les commentaires'),
          ),
          const SizedBox(width: 8),
          _Pill(
            icon: Icons.share_rounded,
            label: 'Partager',
            onTap: () => _share(context),
          ),
          const SizedBox(width: 8),
          _Pill(
            icon: Icons.headphones_rounded,
            label: 'Audio',
            onTap: () => _goAudio(context, ref),
          ),
          const SizedBox(width: 8),
          _RoundIconButton(
            icon: Icons.flag_outlined,
            tooltip: 'Signaler',
            color: theme.colorScheme.onSurfaceVariant,
            onTap: () =>
                _phase3(context, ref, AuthGate.report, 'Les signalements'),
          ),
        ],
      ),
    );
  }

  Future<void> _phase3(
    BuildContext context,
    WidgetRef ref,
    AuthGate gate,
    String subject,
  ) async {
    if (!await requireAuth(context, ref, gate: gate)) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$subject arrivent en Phase 3.')));
  }

  Future<void> _share(BuildContext context) async {
    final artistName = video.artist?.resolvedName;
    final text = artistName == null
        ? 'Découvre « ${video.title} » sur Vibeo.'
        : 'Découvre « ${video.title} » par $artistName sur Vibeo.';
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
  const _Pill({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
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
              Icon(icon, size: 19, color: theme.colorScheme.onSurface),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
