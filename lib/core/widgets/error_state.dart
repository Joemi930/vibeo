import 'package:flutter/material.dart';

/// État d'erreur générique, avec possibilité de réessayer.
///
/// Le message reste volontairement neutre : les erreurs techniques ne sont
/// jamais montrées telles quelles à l'utilisateur.
class ErrorState extends StatelessWidget {
  const ErrorState({
    required this.onRetry,
    this.message = 'Impossible de charger le contenu.',
    super.key,
  });

  final VoidCallback onRetry;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Vérifie ta connexion puis réessaie.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
