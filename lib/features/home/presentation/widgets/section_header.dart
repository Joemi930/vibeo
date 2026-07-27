import 'package:flutter/material.dart';

/// Titre de section de l'accueil, avec un lien « Tout voir » facultatif.
class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.label, this.onSeeAll, super.key});

  final String label;

  /// Absent quand la section n'a pas d'écran dédié : le chevron disparaît
  /// alors, plutôt que de mener nulle part.
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, onSeeAll == null ? 16 : 4, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Tout voir'),
                  SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
