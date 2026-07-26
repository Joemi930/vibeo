import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../core/widgets/video_card.dart';
import '../../domain/playlist.dart';
import '../../../../core/router/app_routes.dart';
import '../providers/library_providers.dart';
import 'playlist_dialogs.dart';
import 'row_list_skeleton.dart';

/// Vignette de couverture d'une playlist, avec repli sur le même placeholder
/// rayé que l'écran de détail quand elle n'a pas (encore) de couverture.
class _PlaylistCoverThumbnail extends ConsumerWidget {
  const _PlaylistCoverThumbnail({required this.coverPath});

  final String? coverPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverPath = this.coverPath;
    if (coverPath == null || coverPath.isEmpty) {
      return const StripedPlaceholder();
    }

    final urlAsync = ref.watch(playlistCoverUrlProvider(coverPath));
    return urlAsync.when(
      data: (url) => url == null
          ? const StripedPlaceholder()
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const StripedPlaceholder(),
            ),
      loading: () => const StripedPlaceholder(),
      error: (_, _) => const StripedPlaceholder(),
    );
  }
}

/// Onglet « Playlists » de la Bibliothèque.
class PlaylistsTab extends ConsumerWidget {
  const PlaylistsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(myPlaylistsProvider);

    return playlistsAsync.when(
      loading: () =>
          const RowListSkeleton(itemBuilder: _buildPlaylistSkeletonRow),
      error: (_, _) => ErrorState(
        message: 'Impossible de charger tes playlists.',
        onRetry: () => ref.invalidate(myPlaylistsProvider),
      ),
      data: (playlists) {
        if (playlists.isEmpty) {
          return EmptyState(
            icon: Icons.playlist_add,
            title: "Aucune playlist pour l'instant",
            message:
                "Regroupe tes clips préférés et retrouve-les d'un geste, "
                'même en mode audio.',
            actionLabel: 'Crée ta première playlist',
            onAction: () => createPlaylistFlow(context, ref),
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: playlists.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _CreatePlaylistRow(
                    onTap: () => createPlaylistFlow(context, ref),
                  );
                }
                return _PlaylistRow(playlist: playlists[index - 1]);
              },
            ),
          ),
        );
      },
    );
  }
}

Widget _buildPlaylistSkeletonRow(BuildContext context) =>
    const PlaylistRowSkeleton();

/// Ligne « Nouvelle playlist », toujours en tête de liste (voir `Library.dc.html`).
class _CreatePlaylistRow extends StatelessWidget {
  const _CreatePlaylistRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.add_rounded,
                color: theme.colorScheme.onPrimaryContainer,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Flexible(
              child: Text(
                'Nouvelle playlist',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PlaylistAction { rename, visibility, delete }

class _PlaylistRow extends ConsumerWidget {
  const _PlaylistRow({required this.playlist});

  final Playlist playlist;

  /// Résout l'URL signée de la couverture actuelle avant d'ouvrir le
  /// dialogue d'édition (le bucket est privé, elle ne se devine pas).
  Future<void> _editPlaylist(BuildContext context, WidgetRef ref) async {
    final coverPath = playlist.coverPath;
    final coverUrl = coverPath == null
        ? null
        : await ref.read(playlistRepositoryProvider).signedCoverUrl(coverPath);
    if (!context.mounted) return;
    await editPlaylistFlow(context, ref, playlist, coverUrl: coverUrl);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push(AppRoutes.playlist(playlist.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 56,
                height: 56,
                child: _PlaylistCoverThumbnail(coverPath: playlist.coverPath),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          playlist.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!playlist.isPublic) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 15,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${playlist.itemCount} clips',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<_PlaylistAction>(
              tooltip: 'Options',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (action) => switch (action) {
                _PlaylistAction.rename => _editPlaylist(context, ref),
                _PlaylistAction.visibility => toggleVisibilityFlow(
                  context,
                  ref,
                  playlist,
                ),
                _PlaylistAction.delete => deletePlaylistFlow(
                  context,
                  ref,
                  playlist,
                ),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: _PlaylistAction.rename,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Modifier'),
                  ),
                ),
                PopupMenuItem(
                  value: _PlaylistAction.visibility,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      playlist.isPublic
                          ? Icons.lock_outline_rounded
                          : Icons.public_rounded,
                    ),
                    title: Text(
                      playlist.isPublic ? 'Rendre privée' : 'Rendre publique',
                    ),
                  ),
                ),
                const PopupMenuItem(
                  value: _PlaylistAction.delete,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline_rounded),
                    title: Text('Supprimer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
