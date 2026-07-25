import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/gradient_button.dart';
import '../../../video/domain/video.dart';
import '../../../video/domain/video_status.dart';
import '../../../video/presentation/providers/video_providers.dart';
import '../providers/upload_providers.dart';

/// Étape 4 — confirmation d'envoi (`Maquettes/Upload4.dc.html`).
///
/// Le statut affiché reflète la vraie valeur renvoyée par le serveur : en
/// Phase 2 la publication est directe (pas de modération avant la Phase 4),
/// le libellé s'adapte donc plutôt que de réafficher « En modération » comme
/// dans la maquette d'origine.
class DoneStep extends ConsumerWidget {
  const DoneStep({required this.published, super.key});

  final Video published;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final message = published.status.isPublished
        ? 'Il est maintenant visible par tous.'
        : 'Statut actuel : ${published.status.label.toLowerCase()}.';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: VibeoColors.of(context).gradient,
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.35),
                      blurRadius: 40,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 60,
                ),
              ),
              const SizedBox(height: 26),
              Text(
                'Clip envoyé !',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '« ${published.title} » a bien été envoyé. $message',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 26),
              _RecapCard(video: published),
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.go(AppRoutes.studio),
                      child: const Text('Voir le Studio'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GradientButton(
                      label: 'Nouveau clip',
                      onPressed: () =>
                          ref.read(uploadControllerProvider.notifier).reset(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecapCard extends ConsumerWidget {
  const _RecapCard({required this.video});

  final Video video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final thumbnailUrl = ref
        .watch(thumbnailUrlProvider(video.thumbnailPath))
        .asData
        ?.value;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 84,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: thumbnailUrl == null
                    ? Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                      )
                    : Image.network(
                        thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  video.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _StatusPill(status: video.status),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final VideoStatus status;

  @override
  Widget build(BuildContext context) {
    final vibeo = VibeoColors.of(context);
    final theme = Theme.of(context);
    final (Color fg, Color bg, IconData icon) = switch (status) {
      VideoStatus.published => (
        vibeo.success,
        vibeo.successContainer,
        Icons.check_circle_outline_rounded,
      ),
      VideoStatus.pendingModeration => (
        vibeo.warning,
        vibeo.warningContainer,
        Icons.schedule_rounded,
      ),
      VideoStatus.processing => (
        theme.colorScheme.onSurfaceVariant,
        theme.colorScheme.surfaceContainerHighest,
        Icons.hourglass_top_rounded,
      ),
      VideoStatus.rejected => (
        theme.colorScheme.error,
        theme.colorScheme.errorContainer,
        Icons.cancel_outlined,
      ),
      VideoStatus.removed => (
        theme.colorScheme.error,
        theme.colorScheme.errorContainer,
        Icons.remove_circle_outline_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
