import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../../auth/presentation/providers/guest_mode_provider.dart';
import '../providers/account_providers.dart';

/// Section « Supprimer mon compte », dans la zone de danger.
///
/// La confirmation exige de **saisir le nom d'utilisateur**, pas un simple
/// « OK » — une action aussi définitive ne doit pas pouvoir être validée par
/// réflexe (double-tap accidentel sur un bouton de dialogue).
class DeleteAccountSection extends ConsumerWidget {
  const DeleteAccountSection({required this.username, super.key});

  final String username;

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteAccountDialog(username: username),
    );
    if (confirmed != true || !context.mounted) return;

    final ok = await ref
        .read(accountControllerProvider.notifier)
        .deleteAccount();
    if (!context.mounted) return;

    if (!ok) {
      final message =
          ref.read(accountControllerProvider).error?.toString() ??
          'Échec de la suppression du compte.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    // Le compte n'existe plus côté serveur : on nettoie l'état local (mode
    // invité + session) puis on renvoie vers la connexion.
    await ref.read(guestModeProvider.notifier).disable();
    await ref.read(authControllerProvider.notifier).signOut();
    if (context.mounted) context.go(AppRoutes.auth);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    final busy = ref.watch(accountControllerProvider).isLoading;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        border: Border.all(color: error),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Supprimer mon compte',
            style: theme.textTheme.titleSmall?.copyWith(
              color: error,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Action définitive et irréversible : tes clips, playlists et '
            'abonnés seront supprimés.',
            style: theme.textTheme.bodySmall?.copyWith(color: error),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: busy ? null : () => _confirmAndDelete(context, ref),
            style: OutlinedButton.styleFrom(
              foregroundColor: error,
              side: BorderSide(color: error),
              minimumSize: const Size(0, 48),
            ),
            child: busy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(error),
                    ),
                  )
                : const Text('Supprimer le compte'),
          ),
        ],
      ),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.username});
  final String username;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _ctrl = TextEditingController();
  bool _matches = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final matches = _ctrl.text.trim() == widget.username;
      if (matches != _matches) setState(() => _matches = matches);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Supprimer définitivement le compte'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cette action est irréversible. Pour confirmer, saisis ton nom '
            'd\'utilisateur « ${widget.username} ».',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              labelText: 'Confirme le nom d\'utilisateur',
              helperText: '@${widget.username}',
              errorText: null,
            ),
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          child: const Text('Supprimer définitivement'),
        ),
      ],
    );
  }
}
