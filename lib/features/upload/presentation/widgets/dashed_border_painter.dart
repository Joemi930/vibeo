import 'package:flutter/material.dart';

/// Trace une bordure pointillée arrondie, pour la zone de dépôt de l'étape 1
/// (`Maquettes/Upload1.dc.html`). Flutter n'a pas de style de bordure
/// pointillée natif : on découpe le contour de l'arrondi en tirets égaux.
class DashedRoundedBorderPainter extends CustomPainter {
  const DashedRoundedBorderPainter({
    required this.color,
    this.radius = 16,
    this.strokeWidth = 2,
    this.dashWidth = 6,
    this.gapWidth = 5,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dashWidth;
  final double gapWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapWidth;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedRoundedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashWidth != dashWidth ||
        oldDelegate.gapWidth != gapWidth;
  }
}
