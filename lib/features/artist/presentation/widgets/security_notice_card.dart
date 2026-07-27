import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Bandeau de sécurité rappelant le traitement du document d'identité.
///
/// Réutilisé dans [BecomeArtistScreen] (avant l'envoi) et
/// [ApplicationStatusScreen] (après, sous une forme plus neutre) — un même
/// message de confiance, cohérent tout au long du parcours.
class SecurityNoticeCard extends StatelessWidget {
  const SecurityNoticeCard({
    required this.message,
    this.icon = Icons.lock_rounded,
    this.emphasized = true,
    super.key,
  });

  final String message;
  final IconData icon;

  /// `true` : bandeau violet fort (avant envoi). `false` : bandeau neutre
  /// discret (après envoi, sur l'écran de suivi).
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vibeo = VibeoColors.of(context);
    final scheme = theme.colorScheme;

    final Color background = emphasized
        ? scheme.primaryContainer
        : scheme.surfaceContainerHigh;
    final Color foreground = emphasized
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final Color iconColor = emphasized ? scheme.onPrimaryContainer : vibeo.info;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: emphasized
            ? Border.all(color: scheme.primary.withValues(alpha: 0.4))
            : Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: emphasized ? 20 : 19, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: foreground,
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
