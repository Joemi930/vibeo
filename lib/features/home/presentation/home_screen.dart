import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/widgets/avatar_circle.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/genre_chip.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../../core/widgets/video_card.dart';
import '../../../core/widgets/vibeo_app_bar.dart';
import '../../profile/presentation/providers/profile_providers.dart';
import '../../video/domain/genre.dart';
import '../../video/domain/video.dart';
import '../../video/presentation/providers/video_providers.dart';

/// Accueil : filtre par genre et fil « Nouveautés ».
///
/// Seul écran sans bouton retour : c'est la racine de la navigation.
/// Tendances et recommandations arrivent en Phase 5 — rien n'est simulé ici.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).asData?.value;

    return Scaffold(
      appBar: VibeoAppBar(
        title: 'Vibeo',
        showBack: false,
        actions: [
          if (profile != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                tooltip: 'Mon profil',
                onPressed: () => context.go(AppRoutes.profile),
                icon: AvatarCircle(
                  name: profile.resolvedName,
                  avatarPath: profile.avatarUrl,
                  radius: 16,
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(publishedVideosProvider);
          ref.invalidate(genresProvider);
        },
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _GenreFilterRow()),
            const SliverToBoxAdapter(child: _SectionTitle('Nouveautés')),
            _VideoFeedSliver(isArtist: profile?.isArtist ?? false),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Rangée horizontale de filtres, « Tous » en tête.
class _GenreFilterRow extends ConsumerWidget {
  const _GenreFilterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genresAsync = ref.watch(genresProvider);
    final selected = ref.watch(selectedGenreProvider);
    final notifier = ref.read(selectedGenreProvider.notifier);

    final genres = genresAsync.asData?.value ?? const <Genre>[];
    if (genres.isEmpty) return const SizedBox(height: 12);

    // Défilement horizontal d'une `Row` plutôt qu'une `ListView` de hauteur
    // fixe : la rangée prend exactement la hauteur de ses pilules, quel que
    // soit le réglage de taille de police du système. Une hauteur codée en dur
    // finissait par rogner le bas des chips.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        children: [
          GenreChip(
            label: 'Tous',
            selected: selected == null,
            onTap: notifier.clear,
          ),
          for (final genre in genres) ...[
            const SizedBox(width: 8),
            GenreChip(
              label: genre.name,
              selected: selected == genre.id,
              onTap: () => notifier.toggle(genre.id),
            ),
          ],
        ],
      ),
    );
  }
}

/// Fil des clips publiés, en grille adaptative (Android étroit → web large).
class _VideoFeedSliver extends ConsumerWidget {
  const _VideoFeedSliver({required this.isArtist});

  final bool isArtist;

  /// Une colonne sur mobile, jusqu'à quatre sur un large écran web.
  static int _columnsFor(double width) {
    if (width < 560) return 1;
    if (width < 900) return 2;
    if (width < 1300) return 3;
    return 4;
  }

  static const double _horizontalPadding = 16;
  static const double _crossSpacing = 16;

  /// Hauteur de cellule calculée plutôt qu'un `childAspectRatio` figé : la
  /// miniature est en 16:9, à quoi s'ajoute un bloc texte dont la hauteur suit
  /// le réglage de taille de police du système.
  static SliverGridDelegate gridDelegate(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = _columnsFor(width);
    final available =
        width - (_horizontalPadding * 2) - (_crossSpacing * (columns - 1));
    final cellWidth = (available / columns).clamp(1.0, double.infinity);
    final textBlock = MediaQuery.textScalerOf(context).scale(66);

    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: _crossSpacing,
      mainAxisSpacing: 18,
      mainAxisExtent: cellWidth * 9 / 16 + textBlock,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videosAsync = ref.watch(publishedVideosProvider);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: videosAsync.when(
        loading: () => const _FeedSkeletonSliver(),
        error: (_, _) => SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: ErrorState(
              message: 'Impossible de charger les clips.',
              onRetry: () => ref.invalidate(publishedVideosProvider),
            ),
          ),
        ),
        data: (videos) {
          if (videos.isEmpty) {
            return SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: EmptyState(
                  icon: Icons.video_library_outlined,
                  title: 'Aucun clip pour le moment',
                  message: isArtist
                      ? 'Publie ton premier clip : il apparaîtra ici aussitôt.'
                      : 'Les clips des artistes vérifiés apparaîtront ici dès '
                            'leur publication.',
                  actionLabel: isArtist ? 'Publier un clip' : null,
                  onAction: isArtist
                      ? () => context.push(AppRoutes.upload)
                      : null,
                ),
              ),
            );
          }
          return _VideoGrid(videos: videos);
        },
      ),
    );
  }
}

class _VideoGrid extends StatelessWidget {
  const _VideoGrid({required this.videos});

  final List<Video> videos;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: _VideoFeedSliver.gridDelegate(context),
      delegate: SliverChildBuilderDelegate((context, index) {
        final video = videos[index];
        return VideoCard(
          video: video,
          onTap: () => context.push(AppRoutes.video(video.id)),
        );
      }, childCount: videos.length),
    );
  }
}

class _FeedSkeletonSliver extends StatelessWidget {
  const _FeedSkeletonSliver();

  @override
  Widget build(BuildContext context) {
    final columns = _VideoFeedSliver._columnsFor(
      MediaQuery.sizeOf(context).width,
    );
    return SliverGrid(
      gridDelegate: _VideoFeedSliver.gridDelegate(context),
      delegate: SliverChildBuilderDelegate(
        (context, index) => const VideoCardSkeleton(),
        childCount: columns * 2,
      ),
    );
  }
}
