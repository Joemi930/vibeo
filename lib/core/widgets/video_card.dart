import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/video/domain/video.dart';
import '../../features/video/presentation/providers/video_providers.dart';
import '../constants/media_limits.dart';
import '../utils/format_utils.dart';
import 'verified_badge.dart';

/// Miniature 16:9 d'un clip, avec pastille de durée.
///
/// Les buckets étant privés, l'URL est signée à la volée. Tant qu'aucune
/// miniature n'existe (le web ne sait pas en extraire), on affiche le motif de
/// rayures diagonales du design system plutôt qu'un vide.
class VideoThumbnail extends ConsumerWidget {
  const VideoThumbnail({
    required this.video,
    this.borderRadius = 12,
    super.key,
  });

  final Video video;
  final double borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref
        .watch(thumbnailUrlProvider(video.thumbnailPath))
        .asData
        ?.value;
    final duration = video.duration;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url == null)
              const StripedPlaceholder()
            else
              // `Image.network` plutôt que `cached_network_image` : ce dernier
              // s'appuie sur un cache fichier qui n'existe pas sur le web, où
              // il échoue silencieusement. Flutter conserve de toute façon les
              // images décodées en mémoire.
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const StripedPlaceholder(),
              ),
            if (duration != null)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    MediaLimits.formatDuration(duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Motif de rayures diagonales servant de visuel de remplacement.
class StripedPlaceholder extends StatelessWidget {
  const StripedPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _StripePainter(
        base: scheme.surfaceContainerHigh,
        stripe: scheme.surfaceContainerHighest,
      ),
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          size: 28,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  const _StripePainter({required this.base, required this.stripe});

  final Color base;
  final Color stripe;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    final paint = Paint()
      ..color = stripe
      ..strokeWidth = 10;
    // Rayures à 135°, espacées de 20 px comme dans le design system.
    for (double x = -size.height; x < size.width + size.height; x += 20) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StripePainter oldDelegate) =>
      oldDelegate.base != base || oldDelegate.stripe != stripe;
}

/// Ligne « artiste · vues » commune aux deux présentations de carte.
class _VideoMeta extends StatelessWidget {
  const _VideoMeta({required this.video});

  final Video video;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artist = video.artist;
    final views = '${formatCompactCount(video.viewCount)} vues';

    return Row(
      children: [
        if (artist != null)
          Flexible(
            child: ArtistNameLabel(
              name: artist.resolvedName,
              isVerified: artist.isVerified,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (artist != null)
          Text(
            ' · ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        // `Flexible` évite un débordement quand la colonne de texte est très
        // étroite (vignette large sur un écran de 320 px, par exemple dans les
        // résultats de recherche) : le compteur de vues s'abrège plutôt que de
        // déborder.
        Flexible(
          child: Text(
            views,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Carte verticale d'un clip (grille de l'accueil, page artiste).
class VideoCard extends StatelessWidget {
  const VideoCard({required this.video, this.onTap, this.width, super.key});

  final Video video;
  final VoidCallback? onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            VideoThumbnail(video: video),
            const SizedBox(height: 8),
            // `Flexible` autorise le bloc texte à se comprimer : dans une
            // grille à hauteur fixe, un titre long ou une police agrandie
            // provoquerait sinon un débordement.
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _VideoMeta(video: video),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ligne horizontale d'un clip (résultats de recherche, Studio).
class VideoListTile extends StatelessWidget {
  const VideoListTile({
    required this.video,
    this.onTap,
    this.trailing,
    this.thumbnailWidth = 150,
    this.dimmed = false,
    super.key,
  });

  final Video video;
  final VoidCallback? onTap;
  final Widget? trailing;
  final double thumbnailWidth;

  /// Atténue la vignette (clip rejeté).
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: thumbnailWidth,
              child: Opacity(
                opacity: dimmed ? 0.6 : 1,
                child: VideoThumbnail(video: video, borderRadius: 10),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _VideoMeta(video: video),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
