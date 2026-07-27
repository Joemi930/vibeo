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
    this.technicalDetail,
    this.needsUnmute = false,
    this.engineGeneration = 0,
  });

  final Video? video;
  final PlaybackMode mode;
  final bool isPlaying;
  final bool isLoading;
  final Duration position;
  final Duration duration;
  final String? errorMessage;

  /// Cause technique brute, affichée sous « Détails techniques ».
  ///
  /// Séparée de [errorMessage] parce qu'elle doit rester lisible **en release** :
  /// sans elle, une panne de lecture chez un utilisateur est indiagnosticable
  /// (`kDebugMode` est faux dans le build servi). Ne contient jamais d'URL
  /// signée ni de jeton — uniquement le code et le message du lecteur.
  final String? technicalDetail;

  /// Le navigateur a refusé le son : la lecture continue en muet et l'interface
  /// propose de le réactiver d'un clic — ce clic étant précisément le geste
  /// utilisateur qui lève le blocage.
  final bool needsUnmute;

  /// Incrémenté à chaque création ou destruction du moteur vidéo.
  ///
  /// Le `VideoPlayerController` est un champ privé du contrôleur, donc invisible
  /// de `ref.watch` : un widget qui le lisait ne se reconstruisait qu'au hasard
  /// de la dernière mutation d'état. Résultat, la vue plateforme reconstruite au
  /// retour du mode audio n'était jamais rattachée à l'écran, et le bouton
  /// « Revenir à la vidéo » paraissait inerte. Ce compteur rend l'événement
  /// observable sans exposer le contrôleur lui-même.
  final int engineGeneration;

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
    String? technicalDetail,
    bool? needsUnmute,
    int? engineGeneration,
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
      technicalDetail: clearError
          ? null
          : (technicalDetail ?? this.technicalDetail),
      needsUnmute: needsUnmute ?? this.needsUnmute,
      engineGeneration: engineGeneration ?? this.engineGeneration,
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

  /// Un changement de mode est en cours.
  ///
  /// Une bascule enchaîne une re-signature d'URL, l'arrêt d'un moteur et
  /// l'initialisation de l'autre : une à trois secondes pendant lesquelles rien
  /// ne bouge à l'écran. L'utilisateur retape donc le bouton. Sans ce verrou,
  /// deux `VideoPlayerController` étaient créés, le premier écrasé sans être
  /// libéré — une vue plateforme fuitée sur le web à chaque double clic.
  bool _switching = false;

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
        technicalDetail: error.toString(),
      );
    }
  }

  Future<void> _startVideo(String url, Duration from) async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _videoController = controller;
    await controller.initialize();
    if (from > Duration.zero) await controller.seekTo(from);

    // On tente d'abord avec le son, comme demandé. Si le navigateur refuse, on
    // rebascule en muet juste en dessous : la lecture muette, elle, est
    // toujours autorisée.
    //
    // Attention au piège : sur le web, `play()` **ne lève pas** d'exception en
    // cas de refus. `video_player_web` intercepte la `DOMException` et la
    // pousse dans le flux d'erreurs du lecteur, où `video_player` la
    // transforme en `VideoPlayerValue.erroneous(...)` — ce qui remet
    // `isInitialized` à faux et fait passer un simple refus de politique
    // navigateur pour une panne de lecture. C'est exactement ce qui affichait
    // « Lecture impossible. Vérifie ta connexion. » sur un clip parfaitement
    // sain. Un `try/catch` autour de `play()` n'attrape donc rien : il faut
    // inspecter l'état du contrôleur après coup.
    await controller.play();
    final refused = _isAutoplayRefusal(controller.value);
    if (refused) {
      await controller.setVolume(0);
      await controller.play();
    }

    // Le listener est attaché avec retry : sur le web, `initialize()` et
    // `play()` peuvent encore être en train de pousser des événements dans
    // le `ValueNotifier` interne, ce qui rend `addListener` fragile. Le
    // vrai crash « addStream » venait de `VibeoAudioHandler` (corrigé dans
    // `vibeo_audio_handler.dart`), mais cette boucle reste une protection
    // utile contre les conditions de concurrence du lecteur vidéo.
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        controller.addListener(_onVideoTick);
        break;
      } on StateError {
        if (attempt == 4) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    state = state.copyWith(
      mode: PlaybackMode.video,
      isLoading: false,
      isPlaying: controller.value.isPlaying,
      duration: controller.value.duration,
      position: from,
      needsUnmute: refused,
      engineGeneration: state.engineGeneration + 1,
      clearError: true,
    );
  }

  /// Relance la lecture en muet après un refus survenu en cours de route.
  Future<void> _recoverFromAutoplayRefusal() async {
    final controller = _videoController;
    if (controller == null) return;
    await controller.setVolume(0);
    await controller.play();
    state = state.copyWith(
      isLoading: false,
      isPlaying: controller.value.isPlaying,
      needsUnmute: true,
      clearError: true,
    );
  }

  /// Rétablit le son après un démarrage muet forcé par le navigateur.
  ///
  /// Appelée depuis un vrai clic : c'est ce geste qui autorise enfin le son.
  Future<void> unmute() async {
    final controller = _videoController;
    if (controller == null) return;
    await controller.setVolume(1);
    if (!controller.value.isPlaying) await controller.play();
    state = state.copyWith(needsUnmute: false, clearError: true);
  }

  /// Vrai si l'erreur portée par le lecteur n'est qu'un refus de démarrage.
  ///
  /// Les navigateurs bloquent la lecture automatique **avec son** tant que
  /// l'utilisateur n'a pas interagi avec la page (`NotAllowedError`), et
  /// annulent une lecture interrompue par un nouveau chargement
  /// (`AbortError`). Ni l'un ni l'autre n'est une panne : les confondre avec
  /// une erreur de flux est ce qui bloquait toute lecture.
  static bool _isAutoplayRefusal(VideoPlayerValue value) {
    if (!value.hasError) return false;
    final raw = (value.errorDescription ?? '').toLowerCase();
    return raw.contains('notallowed') ||
        raw.contains('not allowed') ||
        raw.contains("didn't interact") ||
        raw.contains('did not interact') ||
        raw.contains('user agent') ||
        raw.contains('aborterror') ||
        raw.contains('abort');
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

      // Un refus de démarrage n'est pas une panne : on repasse en muet et on
      // laisse l'utilisateur rétablir le son. Sans cette porte de sortie, tout
      // clip sain s'affichait comme illisible.
      if (_isAutoplayRefusal(value)) {
        unawaited(_recoverFromAutoplayRefusal());
        return;
      }

      logError('erreur de lecture', description);
      state = state.copyWith(
        isLoading: false,
        isPlaying: false,
        errorMessage: _readableError(description),
        technicalDetail: description.isEmpty ? null : description,
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
  ///
  /// Limite connue et assumée : depuis `_onVideoTick`, cette fonction ne reçoit
  /// que `MediaError.message`, car `video_player` jette le code et les détails
  /// en construisant `VideoPlayerValue.erroneous`. Le classement y est donc
  /// approximatif — c'est précisément pourquoi la cause brute est désormais
  /// conservée dans `technicalDetail` et affichée à la demande, y compris en
  /// release. Ne jamais conclure « problème de réseau » sur ce seul message.
  static String _readableError(String raw) {
    final lower = raw.toLowerCase();
    final isFormat =
        lower.contains('format') ||
        lower.contains('src_not_supported') ||
        lower.contains('not supported') ||
        lower.contains('decode') ||
        lower.contains('demuxer');

    if (isFormat) {
      return 'Ce clip utilise un format vidéo que ce navigateur ne sait pas lire.';
    }
    return 'La lecture n\'a pas pu démarrer. Réessaie dans un instant.';
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
    if (video == null || state.isAudioMode || _switching) return;
    _switching = true;
    try {
      await _switchToAudio(video);
    } finally {
      _switching = false;
    }
  }

  Future<void> _switchToAudio(Video video) async {
    final url = await _freshSignedUrl(video);
    if (url == null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Ce clip est indisponible pour le moment.',
      );
      return;
    }

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
  ///
  /// Renvoie `true` si la vidéo repart. Un appelant qui doit aussi naviguer ne
  /// doit **pas** conditionner sa navigation à ce résultat : l'utilisateur a
  /// demandé à quitter le mode audio, il doit quitter l'écran même si le moteur
  /// vidéo refuse de démarrer — l'erreur l'attendra sur le lecteur.
  Future<bool> switchToVideo() async {
    final video = state.video;
    if (video == null || _switching) return false;
    // Pas de garde sur `isAudioMode` : si une bascule audio a échoué à
    // mi-chemin, l'état peut déjà être en mode vidéo alors qu'aucun moteur ne
    // tourne. Refuser d'agir dans ce cas rendait le bouton silencieusement
    // inerte, exactement le symptôme signalé.
    if (!state.isAudioMode && _videoController != null) return true;

    _switching = true;
    try {
      final url = await _freshSignedUrl(video);
      if (url == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Ce clip est indisponible pour le moment.',
        );
        return false;
      }

      final from = state.position;
      state = state.copyWith(isLoading: true);
      await _stopAudio();
      await _startVideo(url, from);
      return true;
    } catch (error, stack) {
      // Sans ce bloc, une exception de `_startVideo` laissait `isLoading` à vrai
      // pour toujours : l'écran restait en chargement, sans message ni moyen de
      // réessayer, et la ligne de navigation qui suivait l'appel n'était jamais
      // atteinte. C'est la cause première du bouton « Revenir à la vidéo » mort.
      logError('retour au mode vidéo impossible', error, stack);
      state = state.copyWith(
        mode: PlaybackMode.video,
        isLoading: false,
        isPlaying: false,
        errorMessage: _readableError(error.toString()),
        technicalDetail: error.toString(),
      );
      return false;
    } finally {
      _switching = false;
    }
  }

  /// URL signée valide pour ce clip, re-signée à chaque changement de mode.
  ///
  /// Les URLs signées expirent au bout d'une heure. Réutiliser celle obtenue à
  /// l'ouverture faisait échouer le passage en mode audio sur une lecture un
  /// peu longue, avec un message accusant à tort l'appareil. La signature est
  /// une simple requête, autant la refaire ; en cas d'échec on retombe sur
  /// l'URL en cache, qui peut encore être valide.
  Future<String?> _freshSignedUrl(Video video) async {
    try {
      final url = await ref
          .read(videoRepositoryProvider)
          .signedVideoUrl(video.videoPath);
      if (url != null) _signedUrl = url;
    } catch (error) {
      logError('re-signature de l\'URL impossible', error);
    }
    return _signedUrl;
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
