import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Pilule de filtre par genre.
///
/// Sélectionnée : dégradé signature et texte blanc, sans bordure.
/// Non sélectionnée : surface neutre et bordure fine.
class GenreChip extends StatelessWidget {
  const GenreChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: selected ? VibeoColors.of(context).gradient : null,
            color: selected ? null : theme.colorScheme.surfaceContainerHigh,
            border: selected
                ? null
                : Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected ? Colors.white : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
