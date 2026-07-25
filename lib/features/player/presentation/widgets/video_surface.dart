import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/media_limits.dart';
import '../../../../core/widgets/floating_back_button.dart';
import '../../../video/domain/video.dart';
import '../../../video/presentation/providers/video_providers.dart';
import '../providers/playback_providers.dart';
import 'scrubber.dart';

/// Bloc vidéo 16:9 avec contrôles superposés (voir `Maquettes/Player.dc.html`).
///
/// Toile toujours sombre, quel que soit le thème de l'app : c'est la
/// convention de tout lecteur vidéo, et c'est ce qui permet aux contrôles
/// blancs de rester lisibles (exception admise à la règle « pas de couleur en
/// dur », voir CLAUDE.md).
class VideoSurface extends ConsumerWidget {
  const VideoSurface({required this.video, this.borderRadius = 0, super.key});

  final Video video;
  final double borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackControllerProvider);
    final controller = ref.read(playbackControllerProvider.notifier);
    final videoController = controller.videoController;
    final thumbnailUrl = ref
        .watch(thumbnailUrlProvider(video.thumbnailPath))
        .asData
        ?.value;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumbnailUrl != null)
                Image.network(
                  thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              if (videoController != null &&
                  videoController.value.isInitialized &&
                  !playback.isAudioMode)
                _VideoFrame(controller: videoController),
              const _DarkVeil(),
              Positioned(
                top: 14,
                left: 12,
                child: FloatingBackButton(fallbackRoute: '/'),
              ),
              if (playback.isAudioMode)
                _AudioModeNotice(onReturnToVideo: controller.switchToVideo)
              else if (playback.errorMessage != null)
                _PlaybackError(
                  message: playback.errorMessage!,
                  onRetry: () => controller.open(video),
                )
              else if (playback.isLoading)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              else
                _PlayPauseButton(
                  isPlaying: playback.isPlaying,
                  onTap: controller.togglePlay,
                ),
              if (!playback.isAudioMode && playback.errorMessage == null)
                _BottomTimeline(
                  position: playback.position,
                  duration: playback.duration,
                  onSeekEnd: controller.seek,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoFrame extends StatelessWidget {
  const _VideoFrame({required this.controller});
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;
    if (size.width <= 0 || size.height <= 0) return const SizedBox.shrink();
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _DarkVeil extends StatelessWidget {
  const _DarkVeil();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x66000000),
            Color(0x00000000),
            Color(0x00000000),
            Color(0xAA000000),
          ],
          stops: [0, 0.3, 0.6, 1],
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.isPlaying, required this.onTap});
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        button: true,
        label: isPlaying ? 'Mettre en pause' : 'Lancer la lecture',
        child: Material(
          color: Colors.black.withValues(alpha: 0.4),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 58,
              height: 58,
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 34,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackError extends StatelessWidget {
  const _PlaybackError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
              onPressed: onRetry,
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioModeNotice extends StatelessWidget {
  const _AudioModeNotice({required this.onReturnToVideo});
  final VoidCallback onReturnToVideo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.headphones_rounded, color: Colors.white, size: 30),
          const SizedBox(height: 8),
          const Text(
            'Lecture audio en cours',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white70),
            ),
            onPressed: onReturnToVideo,
            child: const Text('Revenir à la vidéo'),
          ),
        ],
      ),
    );
  }
}

class _BottomTimeline extends StatelessWidget {
  const _BottomTimeline({
    required this.position,
    required this.duration,
    required this.onSeekEnd,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeekEnd;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 8,
      right: 8,
      bottom: 0,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              MediaLimits.formatDuration(position),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: PlaybackScrubber(
              position: position,
              duration: duration,
              onSeekEnd: onSeekEnd,
              activeColor: Colors.white,
              inactiveColor: Colors.white.withValues(alpha: 0.3),
              thumbColor: Colors.white,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              MediaLimits.formatDuration(duration),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
