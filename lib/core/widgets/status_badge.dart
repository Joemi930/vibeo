import 'package:flutter/material.dart';

import '../../features/video/domain/video_status.dart';
import '../theme/app_colors.dart';

/// Pastille de statut d'un clip, affichée dans le Studio de l'artiste.
class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.status, super.key});

  final VideoStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vibeo = VibeoColors.of(context);

    final (
      Color foreground,
      Color background,
      IconData icon,
    ) = switch (status) {
      VideoStatus.published => (
        vibeo.onSuccessContainer,
        vibeo.successContainer,
        Icons.check_circle_rounded,
      ),
      VideoStatus.pendingModeration => (
        vibeo.warning,
        vibeo.warningContainer,
        Icons.schedule_rounded,
      ),
      VideoStatus.rejected || VideoStatus.removed => (
        theme.colorScheme.onErrorContainer,
        theme.colorScheme.errorContainer,
        Icons.cancel_rounded,
      ),
      VideoStatus.processing => (
        vibeo.info,
        theme.colorScheme.surfaceContainerHigh,
        Icons.hourglass_top_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
