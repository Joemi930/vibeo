import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Barre segmentée en 4 (une par étape) + légende, en tête du parcours de
/// publication (`Maquettes/Upload1-4.dc.html`).
class StepProgressHeader extends StatelessWidget {
  const StepProgressHeader({
    required this.stepIndex,
    required this.stepLabel,
    super.key,
  });

  /// Index 0-based de l'étape courante (0 à 3).
  final int stepIndex;
  final String stepLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradient = VibeoColors.of(context).gradient;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(4, (i) {
              final filled = i <= stepIndex;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: filled ? gradient : null,
                    color: filled ? null : theme.colorScheme.outlineVariant,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'Étape ${stepIndex + 1}/4 · $stepLabel',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
