import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../../core/widgets/vibeo_app_bar.dart';
import '../../../core/widgets/video_card.dart';
import '../../video/domain/video.dart';
import '../domain/playlist.dart';
import 'providers/library_providers.dart';
import 'widgets/playlist_dialogs.dart';

/// Détail d'une playlist : en-tête, puis clips dans l'ordre choisi par son
/// propriétaire (glisser pour réordonner ou retirer).
///
/// Vit sous la branche Bibliothèque du shell (`AppRoutes.playlistSubPath`) :
/// la barre de navigation et le mini-player restent donc visibles.
class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({required this.playlistId, super.key});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistAsync = ref.watch(playlistByIdProvider(playlistId));
    final playlist = playlistAsync.asData?.value;

    return Scaffold(
      appBar: VibeoAppBar(
        title: playlist?.title,
        actions: [
          if (playlist != null)
            IconButton(
              tooltip: 'Modifier la playlist',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editPlaylist(context, ref, playlist),
            ),
        ],
      ),
      body: playlistAsync.when(
        loading: () => const _PlaylistDetailSkeleton(),
        error: (_, _) => ErrorState(
          message: 'Impossible de charger cette playlist.',
          onRetry: () => ref.invalidate(playlistByIdProvider(playlistId)),
        ),
        data: (playlist) {
          if (playlist == null) {
            return EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Playlist introuvable',
              message: 'Elle a peut-être été supprimée ou rendue privée.',
              actionLabel: 'Retour à la bibliothèque',
              onAction: () => context.go(AppRoutes.library),
            );
          }
          return _PlaylistDetailBody(playlist: playlist);
        },
      ),
    );
  }
}

/// Résout l'URL signée de la couverture actuelle avant d'ouvrir le dialogue
/// d'édition (le bucket est privé, elle ne se devine pas).
Future<void> _editPlaylist(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final coverPath = playlist.coverPath;
  final coverUrl = coverPath == null
      ? null
      : await ref.read(playlistRepositoryProvider).signedCoverUrl(coverPath);
  if (!context.mounted) return;
  await editPlaylistFlow(context, ref, playlist, coverUrl: coverUrl);
}

class _PlaylistDetailBody extends ConsumerWidget {
  const _PlaylistDetailBody({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(playlistItemsControllerProvider(playlist.id));
    final controller = ref.read(
      playlistItemsControllerProvider(playlist.id).notifier,
    );

    return Column(
      children: [
        _PlaylistHeader(playlist: playlist),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        Expanded(
          child: itemsAsync.when(
            loading: () =>
                const RowListSkeleton(itemBuilder: _buildItemSkeletonRow),
            error: (_, _) => ErrorState(
              message: 'Impossible de charger le contenu de la playlist.',
              onRetry: () =>
                  ref.invalidate(playlistItemsControllerProvider(playlist.id)),
            ),
            data: (videos) {
              if (videos.isEmpty) {
                return EmptyState(
                  icon: Icons.video_library_outlined,
                  title: 'Cette playlist est vide',
                  message:
                      'Ajoute des clips depuis leur page pour les retrouver '
                      'ici.',
                  actionLabel: 'Découvrir des clips',
                  onAction: () => context.go(AppRoutes.home),
                );
              }
              return _PlaylistItemsList(videos: videos, controller: controller);
            },
          ),
        ),
      ],
    );
  }
}

Widget _buildItemSkeletonRow(BuildContext context) =>
    const VideoListTileSkeleton(thumbnailWidth: 96);

class _PlaylistCover extends ConsumerWidget {
  const _PlaylistCover({required this.coverPath});

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

class _PlaylistHeader extends StatelessWidget {
  const _PlaylistHeader({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = playlist.description?.trim();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 84,
                      height: 84,
                      child: _PlaylistCover(coverPath: playlist.coverPath),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      playlist.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${playlist.itemCount} clips',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    playlist.isPublic
                        ? Icons.public_rounded
                        : Icons.lock_outline_rounded,
                    size: 15,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    playlist.isPublic ? 'Publique' : 'Privée',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Liste réordonnable des clips d'une playlist.
///
/// Chaque ligne se retire d'un glissement horizontal (`Dismissible`) ou d'une
/// icône dédiée ; la poignée de glissement verticale sert au réordonnancement,
/// séparée du reste de la ligne pour ne pas entrer en conflit avec le retrait.
class _PlaylistItemsList extends StatelessWidget {
  const _PlaylistItemsList({required this.videos, required this.controller});

  final List<Video> videos;
  final PlaylistItemsController controller;

  Future<void> _remove(BuildContext context, String videoId) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = await controller.remove(videoId);
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _reorder(
    BuildContext context,
    int oldIndex,
    int newIndex,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = await controller.move(oldIndex, newIndex);
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ReorderableListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          buildDefaultDragHandles: false,
          // `onReorderItem` et non `onReorder` (déprécié) : il fournit déjà
          // l'index de destination corrigé du retrait de l'élément, ce que
          // `PlaylistItemsController.move` attend.
          onReorderItem: (oldIndex, newIndex) =>
              _reorder(context, oldIndex, newIndex),
          children: [
            for (final (index, video) in videos.indexed)
              Dismissible(
                key: ValueKey(video.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                onDismissed: (_) => _remove(context, video.id),
                child: VideoListTile(
                  video: video,
                  thumbnailWidth: 96,
                  onTap: () => context.push(AppRoutes.video(video.id)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Retirer',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => _remove(context, video.id),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: Icon(
                          Icons.drag_handle_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistDetailSkeleton extends StatelessWidget {
  const _PlaylistDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.5,
                    child: SkeletonBox(height: 22),
                  ),
                  SizedBox(height: 10),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.3,
                    child: SkeletonBox(height: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        Expanded(child: RowListSkeleton(itemBuilder: _buildItemSkeletonRow)),
      ],
    );
  }
}
