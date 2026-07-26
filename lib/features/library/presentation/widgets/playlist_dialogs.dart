import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/media_limits.dart';
import '../../../upload/data/thumbnail_picker.dart';
import '../../../upload/data/video_picker.dart' show PickerException;
import '../../domain/playlist.dart';
import '../providers/library_providers.dart';

/// Résultat saisi dans [showPlaylistFormDialog] : titre, visibilité (si le
/// formulaire proposait l'interrupteur) et changement de couverture.
class PlaylistFormResult {
  const PlaylistFormResult({
    required this.title,
    required this.isPublic,
    this.newCover,
    this.removeCover = false,
  });

  final String title;
  final bool isPublic;

  /// Nouvelle couverture choisie, ou `null` si elle n'a pas changé.
  final PickedThumbnail? newCover;

  /// `true` si l'utilisateur a explicitement retiré la couverture existante.
  final bool removeCover;
}

/// Dialogue titre + couverture (+ interrupteur « publique » en création)
/// partagé par la création et l'édition d'une playlist.
///
/// [initialIsPublic] à `null` masque l'interrupteur (édition : la visibilité
/// se change par une action de menu séparée). [initialCoverUrl] est l'URL
/// signée de la couverture actuelle (édition uniquement).
Future<PlaylistFormResult?> showPlaylistFormDialog(
  BuildContext context, {
  required String dialogTitle,
  required String submitLabel,
  String initialTitle = '',
  bool? initialIsPublic,
  String? initialCoverUrl,
}) {
  return showDialog<PlaylistFormResult>(
    context: context,
    builder: (dialogContext) => _PlaylistFormDialog(
      dialogTitle: dialogTitle,
      submitLabel: submitLabel,
      initialTitle: initialTitle,
      initialIsPublic: initialIsPublic,
      initialCoverUrl: initialCoverUrl,
    ),
  );
}

class _PlaylistFormDialog extends StatefulWidget {
  const _PlaylistFormDialog({
    required this.dialogTitle,
    required this.submitLabel,
    required this.initialTitle,
    required this.initialIsPublic,
    required this.initialCoverUrl,
  });

  final String dialogTitle;
  final String submitLabel;
  final String initialTitle;
  final bool? initialIsPublic;
  final String? initialCoverUrl;

  @override
  State<_PlaylistFormDialog> createState() => _PlaylistFormDialogState();
}

class _PlaylistFormDialogState extends State<_PlaylistFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl = TextEditingController(
    text: widget.initialTitle,
  );
  late bool _isPublic = widget.initialIsPublic ?? false;

  PickedThumbnail? _newCover;
  bool _removeCover = false;
  String? _coverError;
  bool _pickingCover = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  bool get _hasCover =>
      _newCover != null ||
      (!_removeCover &&
          widget.initialCoverUrl != null &&
          widget.initialCoverUrl!.isNotEmpty);

  Future<void> _pickCover() async {
    setState(() {
      _pickingCover = true;
      _coverError = null;
    });
    try {
      final picked = await pickThumbnailImage(
        maxBytes: MediaLimits.maxPlaylistCoverBytes,
      );
      if (picked == null) return;
      setState(() {
        _newCover = picked;
        _removeCover = false;
      });
    } on PickerException catch (e) {
      setState(() => _coverError = e.message);
    } finally {
      if (mounted) setState(() => _pickingCover = false);
    }
  }

  void _clearCover() {
    setState(() {
      _newCover = null;
      _removeCover = true;
      _coverError = null;
    });
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(
      PlaylistFormResult(
        title: _titleCtrl.text.trim(),
        isPublic: _isPublic,
        newCover: _newCover,
        removeCover: _removeCover,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showSwitch = widget.initialIsPublic != null;
    return AlertDialog(
      title: Text(widget.dialogTitle),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CoverPicker(
                bytes: _newCover?.bytes,
                imageUrl: _hasCover ? widget.initialCoverUrl : null,
                showPlaceholder: !_hasCover,
                loading: _pickingCover,
                onPick: _pickCover,
                onRemove: _hasCover ? _clearCover : null,
              ),
              if (_coverError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _coverError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
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

/// Aperçu de la couverture choisie, avec actions pour la choisir, la
/// remplacer ou la retirer.
class _CoverPicker extends StatelessWidget {
  const _CoverPicker({
    required this.bytes,
    required this.imageUrl,
    required this.showPlaceholder,
    required this.loading,
    required this.onPick,
    required this.onRemove,
  });

  final Uint8List? bytes;
  final String? imageUrl;
  final bool showPlaceholder;
  final bool loading;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget preview;
    if (loading) {
      preview = const Center(child: CircularProgressIndicator());
    } else if (bytes != null) {
      preview = Image.memory(bytes!, fit: BoxFit.cover);
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      preview = Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _CoverPlaceholder(theme: theme),
      );
    } else {
      preview = _CoverPlaceholder(theme: theme);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: preview,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: loading ? null : onPick,
                icon: const Icon(Icons.image_outlined),
                label: Text(
                  showPlaceholder ? 'Choisir une image' : 'Remplacer',
                ),
              ),
            ),
            if (onRemove != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Retirer la couverture',
                onPressed: loading ? null : onRemove,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.image_outlined,
        size: 40,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Ouvre le dialogue de création, puis appelle
/// `playlistControllerProvider.createDetailed` si l'utilisateur valide.
Future<void> createPlaylistFlow(BuildContext context, WidgetRef ref) async {
  final result = await showPlaylistFormDialog(
    context,
    dialogTitle: 'Nouvelle playlist',
    submitLabel: 'Créer',
    initialIsPublic: false,
  );
  if (result == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final outcome = await ref
      .read(playlistControllerProvider.notifier)
      .createDetailed(
        title: result.title,
        isPublic: result.isPublic,
        cover: result.newCover,
      );
  if (outcome.error != null) {
    messenger.showSnackBar(SnackBar(content: Text(outcome.error!)));
  }
}

/// Ouvre le dialogue d'édition, puis appelle
/// `playlistControllerProvider.edit` si l'utilisateur valide.
///
/// [coverUrl] est l'URL signée déjà résolue de la couverture actuelle (le
/// bucket étant privé, elle ne peut pas être devinée depuis [playlist]
/// seule) ; `null` si la playlist n'en a pas.
Future<void> editPlaylistFlow(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist, {
  String? coverUrl,
}) async {
  final result = await showPlaylistFormDialog(
    context,
    dialogTitle: 'Modifier la playlist',
    submitLabel: 'Enregistrer',
    initialTitle: playlist.title,
    initialCoverUrl: coverUrl,
  );
  if (result == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final message = await ref
      .read(playlistControllerProvider.notifier)
      .edit(
        playlistId: playlist.id,
        ownerId: playlist.ownerId,
        title: result.title,
        newCover: result.newCover,
        removeCover: result.removeCover,
        previousCoverPath: playlist.coverPath,
      );
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
