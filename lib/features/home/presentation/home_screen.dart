import 'package:flutter/material.dart';

/// Accueil — squelette de Phase 1. Le contenu réel (Tendances, Nouveautés,
/// Recommandé) arrive avec la vidéo (P2) et la découverte (P5).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Vibeo')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.home_rounded,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text('Accueil', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Tes clips et recommandations apparaîtront ici.',
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
