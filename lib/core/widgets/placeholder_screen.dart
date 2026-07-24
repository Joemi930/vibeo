import 'package:flutter/material.dart';

/// Écran squelette réutilisable pour les routes prévues mais non encore
/// implémentées (Phase 1). Affiche un titre, une icône et une note « à venir »,
/// correct dans les deux thèmes.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    required this.title,
    required this.icon,
    this.phase,
    super.key,
  });

  final String title;
  final IconData icon;

  /// Phase prévue (ex. « Phase 2 »), affichée en indication.
  final String? phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                phase == null ? 'À venir' : 'À venir · $phase',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
