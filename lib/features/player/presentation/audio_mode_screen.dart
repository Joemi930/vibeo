import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/media_limits.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/verified_badge.dart';
import '../../../core/widgets/vibeo_app_bar.dart';
import '../../video/domain/video.dart';
import '../../video/presentation/providers/video_providers.dart';
import 'providers/playback_providers.dart';
import 'widgets/scrubber.dart';

/// Mode audio seul, plein écran (voir `Maquettes/AudioMode.dc.html`).
///
/// L'identifiant du clip fait partie de l'adresse (`/audio/:videoId`) : l'écran
/// est donc autonome. Si la lecture en cours porte déjà sur ce clip — cas
/// normal, on arrive depuis la pilule « Audio » du lecteur — il se contente
/// d'afficher l'état existant. Sinon (lien partagé, rechargement de page), il
/// charge le clip lui-même et bascule en audio, au lieu d'afficher un écran
/// vide comme le faisait la route `/audio` sans paramètre.
class AudioModeScreen extends ConsumerStatefulWidget {
  const AudioModeScreen({required this.videoId, super.key});

  final String videoId;

  @override
  ConsumerState<AudioModeScreen> createState() => _AudioModeScreenState();
}

class _AudioModeScreenState extends ConsumerState<AudioModeScreen> {
  @override
  void initState() {
    super.initState();
    // Après la première frame : `open` touche l'état d'autres providers, ce
    // qui est interdit pendant la construction de l'arbre.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLoaded());
  }

  Future<void> _ensureLoaded() async {
    final playback = ref.read(playbackControllerProvider);
    if (playback.video?.id == widget.videoId) {
      // Déjà ce clip : on s'assure seulement d'être bien en mode audio.
      if (!playback.isAudioMode) {
        await ref.read(playbackControllerProvider.notifier).switchToAudio();
      }
      return;
    }

    final video = await ref.read(videoByIdProvider(widget.videoId).future);
    if (video == null || !mounted) return;
    final controller = ref.read(playbackControllerProvider.notifier);
    await controller.open(video);
    if (!mounted) return;
    await controller.switchToAudio();
  }

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(playbackControllerProvider);
    final isThisVideo = playback.video?.id == widget.videoId;
    return Scaffold(
      body: SafeArea(
        child: playback.hasMedia && isThisVideo
            ? _AudioContent(playback: playback)
            : const _AudioLoading(),
      ),
    );
  }
}

/// Chargement d'un clip arrivé par lien direct. Volontairement sobre : à ce
/// stade on ne sait pas encore si le clip existe, afficher « aucune lecture »
/// serait trompeur.
class _AudioLoading extends StatelessWidget {
  const _AudioLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _AudioContent extends ConsumerWidget {
  const _AudioContent({required this.playback});

  final PlaybackState playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final video = playback.video!;
    final controller = ref.read(playbackControllerProvider.notifier);
    final thumbnailUrl = ref
        .watch(thumbnailUrlProvider(video.thumbnailPath))
        .asData
        ?.value;

    return Column(
      children: [
        const _AudioHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              children: [
                const SizedBox(height: 10),
                _Artwork(url: thumbnailUrl),
                const SizedBox(height: 26),
                _TitleBlock(video: video),
                const SizedBox(height: 22),
                _ProgressSection(
                  playback: playback,
                  onSeekEnd: controller.seek,
                ),
                const SizedBox(height: 14),
                _Transport(playback: playback, controller: controller),
                const SizedBox(height: 26),
                _BackToVideoButton(
                  onPressed: () async {
                    await controller.switchToVideo();
                    if (context.mounted) VibeoAppBar.popOrGo(context);
                  },
                ),
                const SizedBox(height: 30),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: _QueueSection(),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AudioHeader extends StatelessWidget {
  const _AudioHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => VibeoAppBar.popOrGo(context),
            tooltip: 'Réduire',
            icon: const Icon(Icons.expand_more_rounded, size: 28),
          ),
          Text(
            'LECTURE AUDIO',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          IconButton(
            onPressed: null,
            tooltip: 'Options (bientôt disponibles)',
            icon: Icon(
              Icons.more_horiz_rounded,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: url == null
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: VibeoColors.of(context).gradient,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.music_note_rounded,
                      color: Colors.white,
                      size: 56,
                    ),
                  ),
                )
              : Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: VibeoColors.of(context).gradient,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.video});

  final Video video;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artist = video.artist;
    return Column(
      children: [
        Text(
          video.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 6),
        ArtistNameLabel(
          name: artist?.resolvedName ?? 'Artiste',
          isVerified: artist?.isVerified ?? false,
          badgeSize: 15,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({required this.playback, required this.onSeekEnd});

  final PlaybackState playback;
  final ValueChanged<Duration> onSeekEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        PlaybackScrubber(
          position: playback.position,
          duration: playback.duration,
          onSeekEnd: onSeekEnd,
          activeColor: theme.colorScheme.primary,
          inactiveColor: theme.colorScheme.outlineVariant,
          thumbColor: theme.colorScheme.onSurface,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                MediaLimits.formatDuration(playback.position),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                MediaLimits.formatDuration(playback.duration),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.playback, required this.controller});

  final PlaybackState playback;
  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Icon(Icons.skip_previous_rounded, size: 30, color: disabled),
        IconButton(
          iconSize: 32,
          tooltip: 'Reculer de 10 secondes',
          icon: const Icon(Icons.replay_10_rounded),
          onPressed: () => controller.seek(
            _clampSeek(
              playback.position - const Duration(seconds: 10),
              playback.duration,
            ),
          ),
        ),
        _PlayPauseCircle(
          isPlaying: playback.isPlaying,
          onTap: controller.togglePlay,
        ),
        IconButton(
          iconSize: 32,
          tooltip: 'Avancer de 10 secondes',
          icon: const Icon(Icons.forward_10_rounded),
          onPressed: () => controller.seek(
            _clampSeek(
              playback.position + const Duration(seconds: 10),
              playback.duration,
            ),
          ),
        ),
        Icon(Icons.skip_next_rounded, size: 30, color: disabled),
      ],
    );
  }

  static Duration _clampSeek(Duration value, Duration max) {
    if (value < Duration.zero) return Duration.zero;
    if (max > Duration.zero && value > max) return max;
    return value;
  }
}

class _PlayPauseCircle extends StatelessWidget {
  const _PlayPauseCircle({required this.isPlaying, required this.onTap});

  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      label: isPlaying ? 'Mettre en pause' : 'Lancer la lecture',
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: VibeoColors.of(context).gradient,
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.35),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 70,
              height: 70,
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackToVideoButton extends StatelessWidget {
  const _BackToVideoButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: const Icon(Icons.smart_display_rounded),
        label: const Text('Revenir à la vidéo'),
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          minimumSize: const Size(0, 52),
        ),
      ),
    );
  }
}

class _QueueSection extends StatelessWidget {
  const _QueueSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'À SUIVRE',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "La file d'attente arrive bientôt.",
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
