import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../upload/data/thumbnail_picker.dart';
import '../../../upload/data/video_picker.dart' show PickerException;

/// Sélecteur de pièce d'identité pour la candidature artiste.
///
/// Réutilise [pickThumbnailImage] / [PickedThumbnail] (mêmes contraintes de
/// type MIME et de taille que les autres images de l'app) plutôt qu'un
/// doublon, avec un plafond spécifique de 5 Mo (bucket `identity-docs`).
///
/// L'aperçu est **flouté depuis les octets locaux** (`Image.memory` +
/// `ImageFiltered`) : le bucket `identity-docs` n'a aucune politique de
/// lecture, même pour le propriétaire — on ne peut donc jamais recharger le
/// document depuis le serveur pour l'afficher.
class IdDocumentPicker extends StatelessWidget {
  const IdDocumentPicker({
    required this.document,
    required this.fileName,
    required this.onPick,
    required this.onError,
    super.key,
  });

  /// Document déjà choisi, ou `null` si aucun.
  final PickedThumbnail? document;

  /// Nom de fichier affiché sous l'aperçu.
  final String? fileName;

  final ValueChanged<PickedThumbnail?> onPick;

  /// Message d'erreur à afficher (déjà en français, prêt pour un SnackBar).
  final ValueChanged<String> onError;

  static const int _maxDocumentBytes = 5 * 1024 * 1024;

  Future<void> _pick() async {
    try {
      final picked = await pickThumbnailImage(maxBytes: _maxDocumentBytes);
      if (picked == null) return;
      onPick(picked);
    } on PickerException catch (e) {
      onError(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pièce d\'identité',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          button: true,
          label: document == null
              ? 'Choisir une pièce d\'identité'
              : 'Pièce d\'identité sélectionnée : ${fileName ?? ''}. '
                    'Toucher pour changer.',
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _pick,
            child: Container(
              constraints: const BoxConstraints(minHeight: 120),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: document == null
                  ? _EmptyPickerContent(scheme: scheme)
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: Image.memory(
                            document!.bytes,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Container(color: Colors.black.withValues(alpha: 0.3)),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.badge_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                fileName ?? 'Document sélectionné',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Aperçu flouté pour ta sécurité',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyPickerContent extends StatelessWidget {
  const _EmptyPickerContent({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_photo_alternate_rounded,
            color: scheme.onSurfaceVariant,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            'Choisir une photo de ta pièce d\'identité',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
