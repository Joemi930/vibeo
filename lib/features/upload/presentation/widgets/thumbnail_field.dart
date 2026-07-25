import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// Aperçu de miniature 16:9 avec bouton de remplacement.
///
/// Purement présentationnel : partagé par le parcours de publication et par
/// l'écran de modification d'un clip, qui n'ont pas le même état sous-jacent.
///
/// [bytes] a la priorité sur [imageUrl] : c'est l'image que l'artiste vient de
/// choisir, non encore envoyée.
class ThumbnailField extends StatelessWidget {
  const ThumbnailField({
    required this.onChoose,
    this.bytes,
    this.imageUrl,
    this.onReset,
    this.resetLabel = 'Image du clip',
    this.enabled = true,
    super.key,
  });

  final Uint8List? bytes;
  final String? imageUrl;
  final VoidCallback onChoose;

  /// Affiché uniquement si non nul : revient à la miniature d'origine.
  final VoidCallback? onReset;
  final String resetLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Miniature',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _preview(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: enabled ? onChoose : null,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('Choisir une image'),
            ),
            if (onReset != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: enabled ? onReset : null,
                child: Text(resetLabel),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _preview() {
    final local = bytes;
    if (local != null && local.isNotEmpty) {
      return Image.memory(local, fit: BoxFit.cover);
    }
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _MissingThumbnail(),
      );
    }
    return const _MissingThumbnail();
  }
}

class _MissingThumbnail extends StatelessWidget {
  const _MissingThumbnail();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 6),
          Text(
            'Aucune image : choisis-en une.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
