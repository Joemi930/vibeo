import 'package:flutter/material.dart';

import '../../features/video/domain/artist_summary.dart';
import '../utils/format_utils.dart';
import 'avatar_circle.dart';
import 'verified_badge.dart';

/// Ligne horizontale d'un artiste (avatar, nom vérifié, nombre d'abonnés).
///
/// Partagée par l'onglet Abonnements de la Bibliothèque et l'onglet Artistes
/// de la Recherche : même mise en page dans les deux maquettes.
class ArtistListTile extends StatelessWidget {
  const ArtistListTile({required this.artist, this.onTap, super.key});

  final ArtistSummary artist;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            AvatarCircle(
              name: artist.resolvedName,
              avatarPath: artist.avatarPath,
              radius: 24,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ArtistNameLabel(
                    name: artist.resolvedName,
                    isVerified: artist.isVerified,
                    badgeSize: 15,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatCompactCount(artist.subscriberCount)} abonnés',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
