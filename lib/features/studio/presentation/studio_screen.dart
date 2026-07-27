import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/verified_badge.dart';
import '../../../core/widgets/video_card.dart';
import '../../../core/widgets/vibeo_app_bar.dart';
import '../../auth/domain/profile.dart';
import '../../video/domain/video.dart';
import '../../video/domain/video_status.dart';
import '../../video/presentation/providers/video_providers.dart';
import '../../profile/presentation/providers/profile_providers.dart';

/// Studio artiste : statistiques, publication et gestion de ses clips.
///
/// Un artiste reste un utilisateur ordinaire ; le Studio est sa seule
/// différence (voir `Maquettes/Studio.dc.html`).
class StudioScreen extends ConsumerWidget {
  const StudioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);

    return Scaffold(
      appBar: const VibeoAppBar(title: 'Studio'),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorState(
          message: 'Impossible de charger ton Studio.',
          onRetry: () => ref.invalidate(currentProfileProvider),
        ),
        data: (profile) {
          if (profile == null || !profile.isArtist) {
            return EmptyState(
              icon: Icons.verified_outlined,
              title: 'Le Studio est réservé aux artistes',
              message:
                  'Deviens artiste vérifié pour publier tes clips, suivre tes '
                  'statistiques et gérer ta chaîne.',
              actionLabel: 'Devenir artiste',
              onAction: () => context.push(AppRoutes.becomeArtist),
            );
          }
          return _StudioView(profile: profile);
        },
      ),
    );
  }
}

class _StudioView extends ConsumerWidget {
  const _StudioView({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videosAsync = ref.watch(studioVideosProvider(profile.id));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(studioVideosProvider(profile.id)),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _ArtistHeader(profile: profile),
          const SizedBox(height: 18),
          _StatsRow(
            profile: profile,
            videos: videosAsync.asData?.value ?? const <Video>[],
          ),
          const SizedBox(height: 18),
          _PublishButton(onTap: () => context.push(AppRoutes.upload)),
          const SizedBox(height: 26),
          Text(
            'Mes clips',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          videosAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: ErrorState(
                message: 'Impossible de charger tes clips.',
                onRetry: () => ref.invalidate(studioVideosProvider(profile.id)),
              ),
            ),
            data: (videos) => videos.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: EmptyState(
                      icon: Icons.movie_creation_outlined,
                      title: 'Aucun clip publié',
                      message:
                          'Publie ton premier clip : il apparaîtra ici et sur '
                          'l\'accueil.',
                      actionLabel: 'Publier un clip',
                      onAction: () => context.push(AppRoutes.upload),
                    ),
                  )
                : Column(
                    children: [
                      for (final video in videos)
                        _StudioVideoRow(video: video, artistId: profile.id),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      profile.resolvedName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const VerifiedBadge(size: 18),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '@${profile.username}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Trois compteurs : vues et likes cumulés sur les clips, abonnés du profil.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.profile, required this.videos});

  final Profile profile;
  final List<Video> videos;

  @override
  Widget build(BuildContext context) {
    var views = 0;
    var likes = 0;
    for (final video in videos) {
      views += video.viewCount;
      likes += video.likeCount;
    }

    return Row(
      children: [
        Expanded(
          child: _StatCard(label: 'Vues', value: views),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(label: 'Likes', value: likes),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(label: 'Abonnés', value: profile.subscriberCount),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatCompactCount(value),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Appel à l'action principal : rectangle arrondi (radius 14), pas une pilule.
class _PublishButton extends StatelessWidget {
  const _PublishButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: VibeoColors.of(context).gradient,
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.upload_rounded, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Text(
                  'Publier un clip',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Actions proposées sur un clip du Studio.
enum _VideoAction { edit, delete }

class _StudioVideoRow extends ConsumerWidget {
  const _StudioVideoRow({required this.video, required this.artistId});

  final Video video;
  final String artistId;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce clip ?'),
        content: Text(
          '« ${video.title} » sera définitivement retiré de Vibeo, ainsi que '
          'son fichier vidéo. Cette action est irréversible.',
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
    try {
      await ref.read(videoRepositoryProvider).deleteVideo(video);
      ref.invalidate(studioVideosProvider(artistId));
      ref.invalidate(publishedVideosProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Clip supprimé.')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('La suppression a échoué. Réessaie.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isRejected =
        video.status == VideoStatus.rejected ||
        video.status == VideoStatus.removed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VideoListTile(
          video: video,
          thumbnailWidth: 112,
          dimmed: isRejected,
          onTap: video.isPublished
              ? () => context.push(AppRoutes.video(video.id))
              : null,
          trailing: PopupMenuButton<_VideoAction>(
            tooltip: 'Options',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (action) => switch (action) {
              _VideoAction.edit => context.push(AppRoutes.editVideo(video.id)),
              _VideoAction.delete => _confirmDelete(context, ref),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _VideoAction.edit,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Modifier'),
                ),
              ),
              PopupMenuItem(
                value: _VideoAction.delete,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('Supprimer'),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 124, bottom: 8),
          child: StatusBadge(status: video.status),
        ),
        if (isRejected)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(left: 124, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              // Motif réel écrit par la modération. Le repli générique ne sert
              // plus que pour les clips retirés avant la Phase 4, qui n'ont
              // aucun `moderation_result` : afficher un texte fixe à tout le
              // monde revenait à ne rien expliquer, et l'artiste republiait le
              // même contenu sans comprendre.
              'Motif : ${video.moderationReason ?? 'ce clip a été retiré par la modération.'}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        Divider(color: theme.colorScheme.outlineVariant, height: 1),
      ],
    );
  }
}
