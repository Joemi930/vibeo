import 'package:flutter/material.dart';

/// Bouton « Continuer avec Google » (style outlined pilule) fidèle à la maquette.
class GoogleButton extends StatelessWidget {
  const GoogleButton({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const _GoogleGlyph(size: 18),
      label: const Text('Continuer avec Google'),
    );
  }
}

/// Petite pastille multicolore évoquant le logo Google (SweepGradient).
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            Color(0xFFEA4335),
            Color(0xFFEA4335),
            Color(0xFFFBBC05),
            Color(0xFFFBBC05),
            Color(0xFF34A853),
            Color(0xFF34A853),
            Color(0xFF4285F4),
            Color(0xFF4285F4),
          ],
          stops: [0, .25, .25, .5, .5, .75, .75, 1],
        ),
      ),
    );
  }
}
