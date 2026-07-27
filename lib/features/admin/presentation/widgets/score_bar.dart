import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Barre de score IA, colorée selon le niveau de confiance.
///
/// - >= 80 : succès (vert)
/// - >= 40 : avertissement (jaune)
/// - < 40  : erreur (rouge)
///
/// Utilisé dans les tables d'administration et le panneau d'examen.
class ScoreBar extends StatelessWidget {
  const ScoreBar({required this.score, this.showLabel = true, super.key});

  /// Score entre 0 et 100.
  final double score;

  /// Affiche « Score IA : 72/100 » au-dessus de la barre si vrai.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vibeo = VibeoColors.of(context);

    final Color barColor = score >= 80
        ? vibeo.success
        : score >= 40
        ? vibeo.warning
        : theme.colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabel) ...[
          Text(
            'Score IA : ${score.round()}/100',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            Expanded(
              child: ClipRRect(
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
                        widthFactor: (score / 100).clamp(0.0, 1.0),
                        child: Container(color: barColor),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${score.round()}',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: barColor,
                fontFamily: 'Space Mono',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
