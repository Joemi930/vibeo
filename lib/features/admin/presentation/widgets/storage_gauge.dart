import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Jauge de stockage affichée dans la barre latérale de l'administration.
///
/// Affiche la progression (0-100 %) avec le dégradé signature Vibeo en dessous
/// de 80 %, et la couleur d'avertissement au-delà.
class StorageGauge extends StatelessWidget {
  const StorageGauge({
    required this.bytesUsed,
    required this.bytesLimit,
    super.key,
  });

  final int bytesUsed;
  final int bytesLimit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vibeo = VibeoColors.of(context);

    final ratio = bytesLimit <= 0
        ? 0.0
        : (bytesUsed / bytesLimit).clamp(0.0, 1.0);
    final isWarning = ratio > 0.8;

    final usedGb = bytesUsed / (1024 * 1024 * 1024);
    final limitGb = bytesLimit / (1024 * 1024 * 1024);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Stockage',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(
                Icons.cloud_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: ratio,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isWarning ? vibeo.warning : null,
                        gradient: isWarning ? null : vibeo.gradient,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11.5,
              ),
              children: [
                TextSpan(
                  text: usedGb.toStringAsFixed(1).replaceAll('.', ','),
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: ' / ${limitGb > 0 ? limitGb.round() : 1} Go utilisés',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
