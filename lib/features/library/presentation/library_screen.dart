import 'package:flutter/material.dart';

import '../../../core/widgets/vibeo_app_bar.dart';

/// Bibliothèque — squelette de Phase 1. Playlists, abonnements et historique
/// arrivent en Phase 3.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const VibeoAppBar(title: 'Bibliothèque'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.library_music_rounded,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text('Bibliothèque', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Tes playlists, abonnements et historique apparaîtront ici.',
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
