import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../video/domain/video.dart';
import '../../domain/playlist.dart';
import '../providers/library_providers.dart';

/// Ouvre la feuille « Ajouter à une playlist » pour [video].
///
/// L'appelant doit avoir déjà validé `requireAuth(gate: AuthGate.playlist)` —
/// cette feuille suppose un utilisateur connecté (voir `ActionPillsRow`).
Future<void> showAddToPlaylistSheet(BuildContext context, Video video) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => AddToPlaylistSheet(video: video),
  );
}

/// Feuille glissante listant les playlists de l'utilisateur, avec ajout /
/// retrait du clip et création à la volée.
class AddToPlaylistSheet extends ConsumerStatefulWidget {
  const AddToPlaylistSheet({required this.video, super.key});

  final Video video;

  @override
  ConsumerState<AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends ConsumerState<AddToPlaylistSheet> {
  final _titleController = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  /// Crée une playlist puis y ajoute le clip courant.
  ///
  /// `createDetailed` renvoie l'objet créé : c'est ce qui permet de viser la
  /// bonne playlist. La retrouver par son titre échouerait dès que deux
  /// playlists portent le même nom, ce que rien n'interdit.
  Future<void> _createAndAdd() async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _creating) return;

    setState(() => _creating = true);
    final messenger = ScaffoldMessenger.of(context);

    final result = await ref
        .read(playlistControllerProvider.notifier)
        .createDetailed(title: title);

    if (result.error != null) {
      if (!mounted) return;
      setState(() => _creating = false);
      messenger.showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }

    final created = result.playlist;
    if (created != null) {
      final addError = await ref
          .read(playlistControllerProvider.notifier)
          .addVideo(playlistId: created.id, videoId: widget.video.id);
      if (mounted && addError != null) {
        messenger.showSnackBar(SnackBar(content: Text(addError)));
      }
    }

    if (!mounted) return;
    setState(() => _creating = false);
    _titleController.clear();
  }

  Future<void> _toggle(Playlist playlist, bool contains) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = contains
        ? await ref
              .read(playlistItemsControllerProvider(playlist.id).notifier)
              .remove(widget.video.id)
        : await ref
              .read(playlistControllerProvider.notifier)
              .addVideo(playlistId: playlist.id, videoId: widget.video.id);

    if (!mounted || error == null) return;
    messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playlistsAsync = ref.watch(myPlaylistsProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Text(
                    'Ajouter à une playlist',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(child: _buildList(theme, playlistsAsync)),
                  const Divider(height: 24),
                  _buildCreateRow(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(
    ThemeData theme,
    AsyncValue<List<Playlist>> playlistsAsync,
  ) {
    return playlistsAsync.when(
      data: (playlists) {
        if (playlists.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Tu n\'as encore aucune playlist. Crée-en une ci-dessous.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return ListView.builder(
          shrinkWrap: true,
          itemCount: playlists.length,
          itemBuilder: (context, index) => _PlaylistRow(
            playlist: playlists[index],
            video: widget.video,
            onToggle: _toggle,
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Impossible de charger tes playlists.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => ref.invalidate(myPlaylistsProvider),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _titleController,
            enabled: !_creating,
            maxLength: 60,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Nouvelle playlist',
              counterText: '',
            ),
            onSubmitted: (_) => _createAndAdd(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: _creating ? null : _createAndAdd,
          tooltip: 'Créer la playlist et y ajouter ce clip',
          icon: _creating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

/// Une ligne de playlist, avec indicateur de présence du clip.
///
/// Réutilise `playlistItemsControllerProvider` (déjà chargé par l'écran de
/// détail d'une playlist) plutôt que de dupliquer une requête d'appartenance.
class _PlaylistRow extends ConsumerWidget {
  const _PlaylistRow({
    required this.playlist,
    required this.video,
    required this.onToggle,
  });

  final Playlist playlist;
  final Video video;
  final Future<void> Function(Playlist playlist, bool contains) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(playlistItemsControllerProvider(playlist.id));
    final contains =
        itemsAsync.asData?.value.any((v) => v.id == video.id) ?? false;
    final isBusy = itemsAsync.isLoading;

    return Semantics(
      button: true,
      toggled: contains,
      label: contains
          ? 'Retirer ce clip de la playlist ${playlist.title}'
          : 'Ajouter ce clip à la playlist ${playlist.title}',
      child: ListTile(
        onTap: isBusy ? null : () => onToggle(playlist, contains),
        title: Text(playlist.title),
        subtitle: Text(
          playlist.itemCount > 1
              ? '${playlist.itemCount} clips'
              : '${playlist.itemCount} clip',
        ),
        trailing: SizedBox(
          width: 24,
          height: 24,
          child: isBusy
              ? const CircularProgressIndicator(strokeWidth: 2)
              : Icon(
                  contains
                      ? Icons.check_circle_rounded
                      : Icons.add_circle_outline_rounded,
                  color: contains
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
        ),
      ),
    );
  }
}
