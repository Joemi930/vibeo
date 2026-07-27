import 'package:flutter/material.dart';

/// Résultat d'une boîte de dialogue [showConfirmActionDialog].
///
/// [confirmed] vaut `true` quand l'admin a cliqué sur le bouton de
/// confirmation ; [reason] contient le motif saisi (toujours une chaîne non
/// vide quand [requireReason] était demandé).
typedef ConfirmActionResult = ({bool confirmed, String reason});

/// Boîte de dialogue de confirmation d'une action d'administration.
///
/// [requireReason] affiche un champ texte obligatoire (3 à 500 caractères).
/// [isDestructive] colore le bouton en rouge.
///
/// Retourne `(confirmed: true, reason: '...')` quand l'action est confirmée, ou
/// `(confirmed: false, reason: '')` quand elle est annulée.
Future<ConfirmActionResult> showConfirmActionDialog({
  required BuildContext context,
  required String title,
  String? message,
  String confirmLabel = 'Confirmer',
  bool isDestructive = false,
  bool requireReason = false,
  String reasonLabel = 'Motif',
  String? reasonHint,
}) async {
  final reasonController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  var reason = '';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message != null)
                  Text(
                    message,
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (requireReason) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: reasonController,
                    autofocus: true,
                    maxLines: 3,
                    minLines: 2,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: reasonLabel,
                      hintText: reasonHint,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final trimmed = v?.trim() ?? '';
                      if (trimmed.isEmpty) return 'Le motif est requis.';
                      if (trimmed.length < 3) {
                        return '3 caractères minimum.';
                      }
                      return null;
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (requireReason && !formKey.currentState!.validate()) return;
              reason = reasonController.text.trim();
              Navigator.pop(ctx, true);
            },
            style: isDestructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError,
                  )
                : null,
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );

  reasonController.dispose();
  return (confirmed: confirmed == true, reason: reason);
}
