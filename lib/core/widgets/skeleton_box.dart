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
