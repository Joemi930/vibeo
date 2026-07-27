import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/skeleton_box.dart';
import '../../../../core/widgets/video_card.dart';
import '../../../video/domain/video.dart';

/// Nombre de colonnes de la grille de l'accueil, pour la largeur donnée.
///
/// Dupliqué depuis `home_screen.dart` volontairement, comme une constante de
/// mise en page partagée : les carrousels doivent adopter **exactement** la
/// même largeur de carte que la grille, sinon les deux ne s'alignent plus et
/// l'accueil paraît bricolé sur un large écran.
int carouselColumnsFor(double width) {
  if (width < 560) return 1;
  if (width < 900) return 2;
  if (width < 1300) return 3;
  return 4;
}

/// Largeur d'une carte de carrousel, dérivée de la grille.
///
/// Bornée : sur mobile une colonne unique donnerait une carte pleine largeur,
/// ce qui empêcherait de deviner qu'on peut faire défiler ; sur un très grand
/// écran, des cartes démesurées.
double carouselCardWidth(double width) {
  final columns = carouselColumnsFor(width);
  final raw = (width - 32 - 16 * (columns - 1)) / columns;
  return raw.clamp(200.0, 340.0);
}

/// Rangée horizontale de clips (sections « Tendances » et « Recommandé »).
///
/// Ne remplace pas la grille de « Nouveautés » : les deux cohabitent dans le
/// même `CustomScrollView`. La grille reste telle qu'elle était, testée et
/// éprouvée.
class VideoCarousel extends ConsumerWidget {
  const VideoCarousel({
    required this.videosAsync,
    required this.onRetry,
    super.key,
  });

  final AsyncValue<List<Video>> videosAsync;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = carouselCardWidth(width);
    // Même calcul que la grille : image 16:9 plus le bloc de texte, dont la
    // hauteur suit le réglage de taille de police du système.
    final height =
        cardWidth * 9 / 16 + MediaQuery.textScalerOf(context).scale(66);

    return videosAsync.when(
      loading: () => _CarouselSkeleton(cardWidth: cardWidth, height: height),
      // Une section de découverte en erreur ne doit pas condamner l'accueil :
      // « Nouveautés » reste utilisable juste en dessous. On propose donc de
      // réessayer, discrètement, sans occuper tout l'écran.
      error: (_, _) => _CarouselError(onRetry: onRetry, height: height),
      data: (videos) {
        // Section vide → rien du tout, pas même le titre. C'est le « masquée
        // proprement » de la spécification : un catalogue jeune n'a pas de
        // tendances, et afficher une rangée vide le soulignerait.
        if (videos.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: videos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final video = videos[index];
              return SizedBox(
                width: cardWidth,
                child: VideoCard(
                  video: video,
                  onTap: () => context.push(AppRoutes.video(video.id)),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _CarouselSkeleton extends StatelessWidget {
  const _CarouselSkeleton({required this.cardWidth, required this.height});

  final double cardWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (_, _) =>
            SizedBox(width: cardWidth, child: const VideoCardSkeleton()),
      ),
    );
  }
}

class _CarouselError extends StatelessWidget {
  const _CarouselError({required this.onRetry, required this.height});

  final VoidCallback onRetry;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Cette sélection n\'a pas pu être chargée.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            TextButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
