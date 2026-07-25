import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/require_auth.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/subscribe_button.dart';
import '../../../../core/widgets/verified_badge.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../../social/presentation/providers/social_providers.dart';
import '../../../video/domain/video.dart';
import '../../../../core/utils/format_utils.dart';

/// Ligne artiste du lecteur : avatar, nom vérifié, abonnés, CTA S'abonner.
///
/// Le nom et l'avatar ouvrent la page publique de l'artiste. Le bouton
/// « S'abonner » bascule immédiatement (affichage optimiste), voir
/// [SubscribeController].
class ArtistSubscribeRow extends ConsumerWidget {
  const ArtistSubscribeRow({required this.video, super.key});

  final Video video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final artist = video.artist;
    final avatarUrl = ref
        .watch(avatarSignedUrlProvider(artist?.avatarPath))
        .asData
        ?.value;
    final subscribeState = artist == null
        ? const SubscribeState()
        : ref.watch(subscribeControllerProvider(artist.id));
    final subscriberCount =
        (artist?.subscriberCount ?? 0) + subscribeState.delta;

    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: artist == null ? null : () => _openArtist(context, artist.id),
          child: _Avatar(url: avatarUrl),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: artist == null
                ? null
                : () => _openArtist(context, artist.id),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ArtistNameLabel(
                  name: artist?.resolvedName ?? 'Artiste',
                  isVerified: artist?.isVerified ?? false,
                  badgeSize: 15,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatCompactCount(subscriberCount)} abonnés',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        if (artist != null)
          SubscribeButton(
            isSubscribed: subscribeState.isSubscribed,
            isBusy: subscribeState.isBusy,
            onPressed: () => _subscribe(context, ref, artist.id),
          ),
      ],
    );
  }

  void _openArtist(BuildContext context, String artistId) {
    context.push(AppRoutes.artist(artistId));
  }

  Future<void> _subscribe(
    BuildContext context,
    WidgetRef ref,
    String artistId,
  ) async {
    if (!await requireAuth(context, ref, gate: AuthGate.subscribe)) return;
    ref.read(subscribeControllerProvider(artistId).notifier).toggle();
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: 40,
        height: 40,
        child: url == null
            ? DecoratedBox(
                decoration: BoxDecoration(
                  gradient: VibeoColors.of(context).gradient,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              )
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: VibeoColors.of(context).gradient,
                  ),
                ),
              ),
      ),
    );
  }
}
