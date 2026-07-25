import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/require_auth.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/verified_badge.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../../video/domain/video.dart';
import '../../../../core/utils/format_utils.dart';

/// Ligne artiste du lecteur : avatar, nom vérifié, abonnés, CTA S'abonner.
///
/// Les abonnements sont prévus pour la Phase 3 : le bouton ouvre la garde
/// d'authentification puis annonce l'arrivée de la fonctionnalité, sans
/// fabriquer d'état « abonné » qui n'existe pas encore côté serveur.
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

    return Row(
      children: [
        _Avatar(url: avatarUrl),
        const SizedBox(width: 10),
        Expanded(
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
                '${formatCompactCount(artist?.subscriberCount ?? 0)} abonnés',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _SubscribeButton(onPressed: () => _subscribe(context, ref)),
      ],
    );
  }

  Future<void> _subscribe(BuildContext context, WidgetRef ref) async {
    if (!await requireAuth(context, ref, gate: AuthGate.subscribe)) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Les abonnements arrivent bientôt.')),
    );
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

class _SubscribeButton extends StatelessWidget {
  const _SubscribeButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: VibeoColors.of(context).gradient,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Text(
              "S'abonner",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
