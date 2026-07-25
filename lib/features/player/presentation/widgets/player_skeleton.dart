import 'package:flutter/material.dart';

/// Squelette de chargement du lecteur : silhouette de la vidéo et des
/// métadonnées, animée d'un léger effet « shimmer ».
class PlayerSkeleton extends StatefulWidget {
  const PlayerSkeleton({super.key});

  @override
  State<PlayerSkeleton> createState() => _PlayerSkeletonState();
}

class _PlayerSkeletonState extends State<PlayerSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest;
    final highlight = theme.colorScheme.surfaceContainer;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _block(base, highlight, t, radius: 0),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 18,
                    child: _block(base, highlight, t, widthFactor: 0.7),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 14,
                    child: _block(base, highlight, t, widthFactor: 0.4),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(height: 40, child: _block(base, highlight, t)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _block(
    Color base,
    Color highlight,
    double t, {
    double radius = 10,
    double widthFactor = 1,
  }) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment(-1 + 3 * t, 0),
            end: Alignment(1 + 3 * t, 0),
            colors: [base, highlight, base],
            stops: const [0.35, 0.5, 0.65],
          ),
        ),
      ),
    );
  }
}
