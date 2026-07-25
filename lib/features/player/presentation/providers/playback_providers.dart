import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/utils/dev_log.dart';

import '../../../../core/constants/media_limits.dart';
import '../../../video/domain/video.dart';
import '../../../video/presentation/providers/video_providers.dart';
import '../../data/vibeo_audio_handler.dart';

/// Mode de lecture courant : image + son, ou son seul (écran éteint possible).
enum PlaybackMode { video, audio }

/// État de lecture partagé par le lecteur plein écran et le mini-player.
@immutable
class PlaybackState {
  const PlaybackState({
    this.video,
    this.mode = PlaybackMode.video,
    this.isPlaying = false,
    this.isLoading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.errorMessage,
  });

  final Video? video;
  final PlaybackMode mode;
  final bool isPlaying;
  final bool isLoading;
  final Duration position;
  final Duration duration;
  final String? errorMessage;

  bool get hasMedia => video != null;
  bool get isAudioMode => mode == PlaybackMode.audio;

  /// Progression entre 0 et 1, pour les barres de progression.
  double get progress {
    if (duration.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  PlaybackState copyWith({
    Video? video,
    PlaybackMode? mode,
    bool? isPlaying,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    String? errorMessage,
    bool clearError = false,
    bool clearVideo = false,
  }) {
    return PlaybackState(
      video: clearVideo ? null : (video ?? this.video),
      mode: mode ?? this.mode,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Propriétaire unique de la lecture, vidéo comme audio.
///
/// Vit à la racine de l'application (les providers Riverpod ne sont pas liés à
/// un écran) : **c'est ce qui fait survivre le mini-player à la navigation**,
/// sans singleton ni service à part.
///
/// Un seul moteur est actif à la fois : passer en mode audio libère le
/// `VideoPlayerController` après avoir transmis la position, et inversement.
class PlaybackController extends Notifier<PlaybackState> {
  VideoPlayerController? _videoController;
  VibeoAudioHandler? _audioHandler;
  StreamSubscription<Duration>? _audioPositionSub;
  StreamSubscription<bool>? _audioPlayingSub;

  /// URL signée du média courant, réutilisée lors d'un changement de mode.
  String? _signedUrl;

  /// Vue déjà comptabilisée pour ce clip : évite d'appeler la RPC en boucle.
  bool _viewRecorded = false;

  VideoPlayerController? get videoController => _videoController;

  @override
  PlaybackState build() {
    // Riverpod 3 détruit un provider dès qu'il n'a plus d'abonné. Sans ce
    // maintien explicite, passer du lecteur à un onglet couperait la lecture
    // et détruirait le `VideoPlayerController` en pleine initialisation.
    // C'est précisément ce qui doit survivre : le mini-player.
    ref.keepAlive();
    ref.onDispose(_disposeEngines);
    return const PlaybackState();
  }

  /// Charge un clip et démarre la lecture vidéo.
  Future<void> open(Video video) async {
    if (state.video?.id == video.id && _videoController != null) {
      await play();
      return;
    }

    await _disposeEngines();
    _viewRecorded = false;
    state = PlaybackState(video: video, isLoading: true);

    try {
      final url = await ref
          .read(videoRepositoryProvider)
          .signedVideoUrl(video.videoPath);
      if (url == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Ce clip est indisponible pour le moment.',
        );
        return;
      }
      _signedUrl = url;
      await _startVideo(url, Duration.zero);
    } catch (error, stack) {
      // L'utilisateur ne voit qu'un message neutre, mais la cause réelle doit
      // rester diagnosticable : c'est ce qui manquait quand la lecture échouait
      // sans qu'on puisse distinguer un codec refusé d'un problème de réseau.
      logError('échec d\'ouverture du lecteur', error, stack);
      state = state.copyWith(
        isLoading: false,
        errorMessage: _readableError(error.toString()),
      );
    }
  }

  Future<void> _startVideo(String url, Duration from) async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _videoController = controller;
    await controller.initialize();
    if (from > Duration.zero) await controller.seekTo(from);
    controller.addListener(_onVideoTick);

    // Les navigateurs refusent de démarrer une vidéo avec du son sans geste
    // direct de l'utilisateur. Le `play()` n'échoue pas toujours par exception :
    // il peut aussi être ignoré silencieusement. On lit donc l'état réel du
    // contrôleur plutôt que de supposer que la lecture a démarré — sinon le
    // bouton affiche « pause » alors que rien ne bouge.
    try {
      await controller.play();
    } catch (error) {
      logError('démarrage automatique refusé', error);
    }

    state = state.copyWith(
      mode: PlaybackMode.video,
      isLoading: false,
      isPlaying: controller.value.isPlaying,
      duration: controller.value.duration,
      position: from,
      clearError: true,
    );
  }

  void _onVideoTick() {
    final controller = _videoController;
    if (controller == null) return;
    final value = controller.value;

    // Une erreur peut survenir bien après l'initialisation (flux interrompu,
    // image que le décodeur refuse en cours de route) : sans ce relais, le
    // lecteur restait figé sur un écran noir sans explication.
    if (value.hasError) {
      final description = value.errorDescription ?? '';
      logError('erreur de lecture', description);
      state = state.copyWith(
        isLoading: false,
        isPlaying: false,
        errorMessage: _readableError(description),
      );
      return;
    }

    if (!value.isInitialized) return;
    state = state.copyWith(
      position: value.position,
      duration: value.duration,
      isPlaying: value.isPlaying,
      isLoading: value.isBuffering,
    );
    _maybeRecordView(value.position);
  }

  /// Traduit l'erreur du lecteur en message utile.
  ///
  /// Sur le web, `video_player` remonte le code `MediaError` du navigateur :
  /// 4 (`MEDIA_ELEMENT_ERROR: Format error`) signifie que le fichier arrive bien
  /// mais que le décodeur refuse ses codecs — un cas radicalement différent
  /// d'une coupure réseau, et qu'il ne sert à rien de « réessayer ».
  static String _readableError(String raw) {
    final lower = raw.toLowerCase();
    final isFormat =
        lower.contains('format') ||
        lower.contains('src_not_supported') ||
        lower.contains('not supported') ||
        lower.contains('decode');

    final message = isFormat
        ? 'Ce clip utilise un format vidéo que ce navigateur ne sait pas lire.'
        : 'Lecture impossible. Vérifie ta connexion.';

    if (!kDebugMode || raw.isEmpty) return message;
    return '$message\n\n[debug] $raw';
  }

  /// Comptabilise la vue une fois le seuil de lecture franchi.
  ///
  /// Le serveur applique de toute façon la même règle des 10 secondes et son
  /// anti-spam : cet appel unique évite simplement du trafic inutile.
  void _maybeRecordView(Duration position) {
    if (_viewRecorded) return;
    if (position < MediaLimits.viewCountThreshold) return;
    final video = state.video;
    if (video == null) return;

    _viewRecorded = true;
    unawaited(
      ref
          .read(videoRepositoryProvider)
          .recordView(
            videoId: video.id,
            watchedSeconds: position.inSeconds,
            sessionKey: ref.read(viewSessionKeyProvider),
          )
          .catchError((_) => false),
    );
  }

  Future<void> play() async {
    if (state.isAudioMode) {
      await _audioHandler?.play();
    } else {
      await _videoController?.play();
    }
    state = state.copyWith(isPlaying: true);
  }

  Future<void> pause() async {
    if (state.isAudioMode) {
      await _audioHandler?.pause();
    } else {
      await _videoController?.pause();
    }
    state = state.copyWith(isPlaying: false);
  }

  Future<void> togglePlay() => state.isPlaying ? pause() : play();

  Future<void> seek(Duration position) async {
    if (state.isAudioMode) {
      await _audioHandler?.seek(position);
    } else {
      await _videoController?.seekTo(position);
    }
    state = state.copyWith(position: position);
  }

  /// Bascule en lecture audio seule : la position est transmise au moteur
  /// audio, et le moteur vidéo est libéré.
  ///
  /// Sur Android, `audio_service` prend alors le relais : notification média et
  /// lecture écran éteint. Sur le web, la lecture continue mais sans
  /// notification système — le navigateur ne le permet pas.
  Future<void> switchToAudio() async {
    final video = state.video;
    final url = _signedUrl;
    if (video == null || url == null || state.isAudioMode) return;

    final from = state.position;
    state = state.copyWith(isLoading: true);

    await _disposeVideo();

    try {
      final handler = await _ensureAudioHandler();
      final thumbnailUrl = await ref
          .read(videoRepositoryProvider)
          .signedThumbnailUrl(video.thumbnailPath);

      final duration = await handler.setTrack(
        id: video.id,
        url: url,
        title: video.title,
        artist: video.artist?.resolvedName ?? 'Vibeo',
        artUri: thumbnailUrl,
        initialPosition: from,
      );
      await handler.play();
      _listenToAudio(handler);

      state = state.copyWith(
        mode: PlaybackMode.audio,
        isLoading: false,
        isPlaying: true,
        duration: duration ?? state.duration,
        position: from,
        clearError: true,
      );
    } catch (_) {
      // Repli : on revient à la vidéo plutôt que de laisser l'app muette.
      await _startVideo(url, from);
      state = state.copyWith(
        errorMessage: 'Le mode audio n\'est pas disponible sur cet appareil.',
      );
    }
  }

  /// Revient à la lecture vidéo, à la position atteinte en audio.
  Future<void> switchToVideo() async {
    final url = _signedUrl;
    if (url == null || !state.isAudioMode) return;

    final from = state.position;
    state = state.copyWith(isLoading: true);
    await _stopAudio();
    await _startVideo(url, from);
  }

  /// Ferme le lecteur (croix du mini-player) et libère toutes les ressources.
  Future<void> close() async {
    await _disposeEngines();
    _signedUrl = null;
    _viewRecorded = false;
    state = const PlaybackState();
  }

  Future<VibeoAudioHandler> _ensureAudioHandler() async {
    final existing = _audioHandler;
    if (existing != null) return existing;

    // Initialisation paresseuse : `AudioService.init` touche à la configuration
    // Android (service au premier plan). La faire au premier passage en mode
    // audio évite d'alourdir le démarrage de l'app et de casser le web.
    final handler = await AudioService.init(
      builder: VibeoAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'io.vibeo.app.audio',
        androidNotificationChannelName: 'Lecture Vibeo',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    _audioHandler = handler;
    return handler;
  }

  void _listenToAudio(VibeoAudioHandler handler) {
    _audioPositionSub?.cancel();
    _audioPlayingSub?.cancel();
    _audioPositionSub = handler.player.positionStream.listen((position) {
      state = state.copyWith(position: position);
      _maybeRecordView(position);
    });
    _audioPlayingSub = handler.player.playingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing);
    });
  }

  Future<void> _disposeVideo() async {
    final controller = _videoController;
    _videoController = null;
    if (controller == null) return;
    controller.removeListener(_onVideoTick);
    await controller.dispose();
  }

  Future<void> _stopAudio() async {
    await _audioPositionSub?.cancel();
    await _audioPlayingSub?.cancel();
    _audioPositionSub = null;
    _audioPlayingSub = null;
    await _audioHandler?.stop();
  }

  Future<void> _disposeEngines() async {
    await _disposeVideo();
    await _stopAudio();
  }
}

final playbackControllerProvider =
    NotifierProvider<PlaybackController, PlaybackState>(PlaybackController.new);
