import 'package:flutter/material.dart';

/// Bloc gris animé d'un effet « shimmer », utilisé pendant les chargements.
///
/// Reproduit la mise en page finale plutôt que d'afficher un simple indicateur
/// circulaire (voir `Maquettes/SkeletonHome.dc.html`). Animation faite à la
/// main : aucune dépendance supplémentaire.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({this.width, this.height, this.borderRadius, super.key});

  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHigh;
    final highlight = scheme.surfaceContainerHighest;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Déplace la bande claire de la gauche vers la droite en boucle.
        final shift = _controller.value * 2 - 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment(shift - 1, 0),
              end: Alignment(shift + 1, 0),
              colors: [base, highlight, base],
              stops: const [0.25, 0.5, 0.75],
            ),
          ),
        );
      },
    );
  }
}

/// Squelette d'une carte de clip, calqué sur la mise en page de `VideoCard`.
class VideoCardSkeleton extends StatelessWidget {
  const VideoCardSkeleton({this.width, super.key});

  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: SkeletonBox(borderRadius: BorderRadius.circular(12)),
          ),
          const SizedBox(height: 8),
          const SkeletonBox(height: 12),
          const SizedBox(height: 6),
          const FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: 0.6,
            child: SkeletonBox(height: 10),
          ),
        ],
      ),
    );
  }
}

/// Squelette d'une ligne de clip horizontale, calqué sur `VideoListTile`.
///
/// Partagé par la Bibliothèque (historique, contenu d'une playlist) et la
/// Recherche (résultats « Clips ») : même mise en page, seule la largeur de
/// vignette diffère d'un écran à l'autre.
class VideoListTileSkeleton extends StatelessWidget {
  const VideoListTileSkeleton({this.thumbnailWidth = 150, super.key});

  final double thumbnailWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: thumbnailWidth,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: SkeletonBox(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SkeletonBox(height: 14),
                const SizedBox(height: 8),
                const FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.45,
                  child: SkeletonBox(height: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Colonne de squelettes centrée et contrainte en largeur, commune à tout
/// écran présentant une liste verticale (Bibliothèque, Recherche) pendant son
/// chargement.
class RowListSkeleton extends StatelessWidget {
  const RowListSkeleton({
    required this.itemBuilder,
    this.count = 6,
    this.maxWidth = 720,
    super.key,
  });

  final WidgetBuilder itemBuilder;
  final int count;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          itemCount: count,
          itemBuilder: (context, _) => itemBuilder(context),
        ),
      ),
    );
  }
}

/// Squelette d'une ligne d'artiste (avatar rond + nom), abonnements/recherche.
class ArtistRowSkeleton extends StatelessWidget {
  const ArtistRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const SkeletonBox(
            width: 44,
            height: 44,
            borderRadius: BorderRadius.all(Radius.circular(22)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.5,
                  child: SkeletonBox(height: 14),
                ),
                const SizedBox(height: 8),
                const FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.3,
                  child: SkeletonBox(height: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
