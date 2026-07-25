import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/playlist.dart';
import '../providers/library_providers.dart';

/// Résultat saisi dans [showPlaylistFormDialog] : titre, et visibilité si le
/// formulaire proposait l'interrupteur.
class PlaylistFormResult {
  const PlaylistFormResult({required this.title, required this.isPublic});

  final String title;
  final bool isPublic;
}

/// Dialogue titre (+ interrupteur « publique » en création) partagé par la
/// création et le renommage d'une playlist.
///
/// [initialIsPublic] à `null` masque l'interrupteur (renommage : la
/// visibilité se change par une action de menu séparée).
Future<PlaylistFormResult?> showPlaylistFormDialog(
  BuildContext context, {
  required String dialogTitle,
  required String submitLabel,
  String initialTitle = '',
  bool? initialIsPublic,
}) {
  return showDialog<PlaylistFormResult>(
    context: context,
    builder: (dialogContext) => _PlaylistFormDialog(
      dialogTitle: dialogTitle,
      submitLabel: submitLabel,
      initialTitle: initialTitle,
      initialIsPublic: initialIsPublic,
    ),
  );
}

class _PlaylistFormDialog extends StatefulWidget {
  const _PlaylistFormDialog({
    required this.dialogTitle,
    required this.submitLabel,
    required this.initialTitle,
    required this.initialIsPublic,
  });

  final String dialogTitle;
  final String submitLabel;
  final String initialTitle;
  final bool? initialIsPublic;

  @override
  State<_PlaylistFormDialog> createState() => _PlaylistFormDialogState();
}

class _PlaylistFormDialogState extends State<_PlaylistFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl = TextEditingController(
    text: widget.initialTitle,
  );
  late bool _isPublic = widget.initialIsPublic ?? false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(
      PlaylistFormResult(title: _titleCtrl.text.trim(), isPublic: _isPublic),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showSwitch = widget.initialIsPublic != null;
    return AlertDialog(
      title: Text(widget.dialogTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _titleCtrl,
              autofocus: true,
              maxLength: 60,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'Titre'),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Le titre est obligatoire.'
                  : null,
            ),
            if (showSwitch)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Playlist publique'),
                subtitle: const Text('Visible par les autres utilisateurs.'),
                value: _isPublic,
                onChanged: (value) => setState(() => _isPublic = value),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
      ],
    );
  }
}

/// Ouvre le dialogue de création, puis appelle
/// `playlistControllerProvider.create` si l'utilisateur valide.
Future<void> createPlaylistFlow(BuildContext context, WidgetRef ref) async {
  final result = await showPlaylistFormDialog(
    context,
    dialogTitle: 'Nouvelle playlist',
    submitLabel: 'Créer',
    initialIsPublic: false,
  );
  if (result == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final message = await ref
      .read(playlistControllerProvider.notifier)
      .create(title: result.title, isPublic: result.isPublic);
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Ouvre le dialogue de renommage, puis appelle
/// `playlistControllerProvider.rename` si l'utilisateur valide.
Future<void> renamePlaylistFlow(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final result = await showPlaylistFormDialog(
    context,
    dialogTitle: 'Renommer la playlist',
    submitLabel: 'Enregistrer',
    initialTitle: playlist.title,
  );
  if (result == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final message = await ref
      .read(playlistControllerProvider.notifier)
      .rename(playlistId: playlist.id, title: result.title);
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Bascule publique ↔ privée sans dialogue (action réversible d'un menu).
Future<void> toggleVisibilityFlow(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = await ref
      .read(playlistControllerProvider.notifier)
      .setVisibility(playlistId: playlist.id, isPublic: !playlist.isPublic);
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Confirme puis supprime une playlist.
Future<void> deletePlaylistFlow(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Supprimer cette playlist ?'),
      content: Text(
        '« ${playlist.title} » sera définitivement supprimée. Cette action '
        'est irréversible.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final message = await ref
      .read(playlistControllerProvider.notifier)
      .delete(playlist.id);
  messenger.showSnackBar(
    SnackBar(content: Text(message ?? 'Playlist supprimée.')),
  );
}
