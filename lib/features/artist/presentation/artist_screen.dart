import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/require_auth.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/avatar_circle.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/floating_back_button.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../../core/widgets/subscribe_button.dart';
import '../../../core/widgets/verified_badge.dart';
import '../../../core/widgets/video_card.dart';
import '../../auth/domain/profile.dart';
import '../../profile/presentation/providers/profile_providers.dart';
import '../../social/presentation/providers/social_providers.dart';
import '../../video/presentation/providers/video_providers.dart';

/// Page publique d'un artiste (voir `Maquettes/Artist.dc.html`).
///
/// Simplifiée à deux onglets — Clips et À propos — pour cette phase : les
/// playlists publiques d'artiste ne sont pas encore au programme.
class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({required this.artistId, super.key});

  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileByIdProvider(artistId));

    return Scaffold(
      body: profileAsync.when(
        loading: () => const _ArtistSkeleton(),
        error: (_, _) => SafeArea(
          child: Stack(
            children: [
              Center(
                child: ErrorState(
                  message: 'Impossible de charger cet artiste.',
                  onRetry: () => ref.invalidate(profileByIdProvider(artistId)),
                ),
              ),
              const Positioned(top: 8, left: 12, child: FloatingBackButton()),
            ],
          ),
        ),
        data: (profile) => profile == null
            ? const _ArtistNotFound()
            : _ArtistBody(profile: profile, artistId: artistId),
      ),
    );
  }
}

class _ArtistNotFound extends StatelessWidget {
  const _ArtistNotFound();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          EmptyState(
            icon: Icons.person_off_outlined,
            title: 'Artiste introuvable',
            message: "Ce profil n'existe pas ou a été supprimé.",
            actionLabel: "Retour à l'accueil",
            onAction: () => context.go(AppRoutes.home),
          ),
          const Positioned(top: 8, left: 12, child: FloatingBackButton()),
        ],
      ),
    );
  }
}

/// Bannière + avatar superposé + identité + onglets, une fois le profil chargé.
class _ArtistBody extends ConsumerWidget {
  const _ArtistBody({required this.profile, required this.artistId});

  final Profile profile;
  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscribeState = ref.watch(subscribeControllerProvider(artistId));
    final subscriberCount = profile.subscriberCount + subscribeState.delta;
    final videosAsync = ref.watch(artistVideosProvider(artistId));
    final videoCount = videosAsync.asData?.value.length;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          _Banner(profile: profile),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: _Identity(
              profile: profile,
              subscriberCount: subscriberCount,
              videoCount: videoCount,
              subscribeState: subscribeState,
              artistId: artistId,
            ),
          ),
          const SizedBox(height: 14),
          const TabBar(
            tabs: [
              Tab(text: 'Clips'),
              Tab(text: 'À propos'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _ClipsTab(artistId: artistId),
                _AboutTab(profile: profile),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bannière avec avatar rond superposé et flèche de retour.
///
/// Affiche l'image de `profile.bannerPath` si l'artiste en a choisi une
/// (résolue en URL signée, bucket privé) ; retombe sur le dégradé de thème
/// sinon, pour ne jamais laisser de trou visuel.
class _Banner extends ConsumerWidget {
  const _Banner({required this.profile});

  final Profile profile;

  static const double _bannerHeight = 130;
  static const double _avatarSize = 78;
  static const double _avatarOverlap = 30;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final topInset = MediaQuery.of(context).padding.top;
    final bannerUrl = ref
        .watch(avatarSignedUrlProvider(profile.bannerPath))
        .asData
        ?.value;

    return SizedBox(
      height: _bannerHeight + _avatarOverlap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: _bannerHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: bannerUrl == null
                  ? VibeoColors.of(context).gradient
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: bannerUrl == null
                ? null
                : Image.network(
                    bannerUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: VibeoColors.of(context).gradient,
                      ),
                    ),
                  ),
          ),
          Positioned(
            top: topInset + 6,
            left: 12,
            child: const FloatingBackButton(),
          ),
          Positioned(
            left: 20,
            top: _bannerHeight - _avatarSize + _avatarOverlap,
            child: Container(
              width: _avatarSize,
              height: _avatarSize,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: AvatarCircle(
                name: profile.resolvedName,
                avatarPath: profile.avatarUrl,
                radius: (_avatarSize - 8) / 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Identity extends ConsumerWidget {
  const _Identity({
    required this.profile,
    required this.subscriberCount,
    required this.videoCount,
    required this.subscribeState,
    required this.artistId,
  });

  final Profile profile;
  final int subscriberCount;
  final int? videoCount;
  final SubscribeState subscribeState;
  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bio = profile.bio?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ArtistNameLabel(
          name: profile.resolvedName,
          isVerified: profile.isArtist,
          badgeSize: 20,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _Stat(count: subscriberCount, label: 'abonnés'),
            const SizedBox(width: 16),
            _Stat(count: videoCount ?? 0, label: 'clips'),
          ],
        ),
        if (bio != null && bio.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            bio,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 16),
        SubscribeButton(
          expand: true,
          isSubscribed: subscribeState.isSubscribed,
          isBusy: subscribeState.isBusy,
          onPressed: () => _subscribe(context, ref),
        ),
      ],
    );
  }

  Future<void> _subscribe(BuildContext context, WidgetRef ref) async {
    if (!await requireAuth(context, ref, gate: AuthGate.subscribe)) return;
    ref.read(subscribeControllerProvider(artistId).notifier).toggle();
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.count, required this.label});

  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: formatCompactCount(count),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: ' $label',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClipsTab extends ConsumerWidget {
  const _ClipsTab({required this.artistId});

  final String artistId;

  static int _columnsFor(double width) {
    if (width < 840) return 2;
    if (width < 1300) return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videosAsync = ref.watch(artistVideosProvider(artistId));

    return videosAsync.when(
      loading: () => const _ClipsGridSkeleton(),
      error: (_, _) => Center(
        child: ErrorState(
          message: 'Impossible de charger les clips.',
          onRetry: () => ref.invalidate(artistVideosProvider(artistId)),
        ),
      ),
      data: (videos) {
        if (videos.isEmpty) {
          return const EmptyState(
            icon: Icons.video_library_outlined,
            title: 'Aucun clip publié',
            message: "Cet artiste n'a pas encore publié de clip.",
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = _columnsFor(constraints.maxWidth);
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 14,
                mainAxisSpacing: 18,
                childAspectRatio: 0.78,
              ),
              itemCount: videos.length,
              itemBuilder: (context, index) {
                final video = videos[index];
                return VideoCard(
                  video: video,
                  onTap: () => context.push(AppRoutes.video(video.id)),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ClipsGridSkeleton extends StatelessWidget {
  const _ClipsGridSkeleton();

  @override
  Widget build(BuildContext context) {
    final columns = _ClipsTab._columnsFor(MediaQuery.sizeOf(context).width);
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 14,
        mainAxisSpacing: 18,
        childAspectRatio: 0.78,
      ),
      itemCount: columns * 2,
      itemBuilder: (context, index) => const VideoCardSkeleton(),
    );
  }
}

class _AboutTab extends StatelessWidget {
  const _AboutTab({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bio = profile.bio?.trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BIO',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            bio == null || bio.isEmpty
                ? "Cet artiste n'a pas encore ajouté de biographie."
                : bio,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 20),
          Text(
            'MEMBRE DEPUIS',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _memberSince(profile.createdAt),
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  static const _months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  static String _memberSince(DateTime date) =>
      '${_months[date.month - 1]} ${date.year}';
}

class _ArtistSkeleton extends StatelessWidget {
  const _ArtistSkeleton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: double.infinity,
                height: 130,
                child: SkeletonBox(borderRadius: BorderRadius.zero),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(height: 22, width: 160),
                    SizedBox(height: 10),
                    SkeletonBox(height: 14, width: 120),
                    SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: SkeletonBox(height: 48),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Positioned(top: 8, left: 12, child: FloatingBackButton()),
        ],
      ),
    );
  }
}
