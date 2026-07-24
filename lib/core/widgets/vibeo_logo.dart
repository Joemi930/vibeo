import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Logo « Onde » de Vibeo : un V formé de 5 barres d'égaliseur (la centrale
/// plus courte, en accent). Barres extérieures en dégradé signature, barre
/// centrale en accent violet clair.
class VibeoLogo extends StatelessWidget {
  const VibeoLogo({this.size = 58, super.key});

  final double size;

  // Hauteurs relatives des 5 barres (proportions de la maquette SVG).
  static const List<double> _heights = [0.66, 0.44, 0.26, 0.44, 0.66];

  @override
  Widget build(BuildContext context) {
    final barWidth = size * 0.12;
    final gap = size * 0.07;
    return SizedBox(
      height: size,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _heights.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Container(
              width: barWidth,
              height: size * _heights[i],
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(barWidth / 2),
                gradient: i == 2 ? null : AppColors.signatureGradient,
                color: i == 2 ? AppColors.dAccent : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
