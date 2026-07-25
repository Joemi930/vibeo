import 'package:flutter/material.dart';

import '../../../../core/constants/media_limits.dart';

/// Barre de progression déplaçable, partagée par le lecteur vidéo (overlay
/// blanc sur voile noir) et le mode audio (couleurs du thème).
///
/// Affiche localement la valeur en cours de glissement avant d'appeler
/// [onSeekEnd], pour éviter de solliciter le moteur de lecture à chaque pixel.
class PlaybackScrubber extends StatefulWidget {
  const PlaybackScrubber({
    required this.position,
    required this.duration,
    required this.onSeekEnd,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    super.key,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeekEnd;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;

  @override
  State<PlaybackScrubber> createState() => _PlaybackScrubberState();
}

class _PlaybackScrubberState extends State<PlaybackScrubber> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration.inMilliseconds;
    final canSeek = totalMs > 0;
    final value = canSeek
        ? (widget.position.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;

    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: widget.activeColor,
        inactiveTrackColor: widget.inactiveColor,
        thumbColor: widget.thumbColor,
        overlayColor: widget.thumbColor.withValues(alpha: 0.16),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
        trackShape: const RectangularSliderTrackShape(),
      ),
      child: Slider(
        value: _dragValue ?? value,
        label: MediaLimits.formatDuration(
          Duration(milliseconds: (value * totalMs).round()),
        ),
        onChanged: canSeek ? (next) => setState(() => _dragValue = next) : null,
        onChangeEnd: canSeek
            ? (next) {
                widget.onSeekEnd(
                  Duration(milliseconds: (next * totalMs).round()),
                );
                setState(() => _dragValue = null);
              }
            : null,
      ),
    );
  }
}
