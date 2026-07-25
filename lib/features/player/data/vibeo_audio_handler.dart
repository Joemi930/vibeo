import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// Pont entre `just_audio` (le moteur de lecture) et `audio_service`
/// (la notification média du système et la lecture en arrière-plan).
///
/// C'est ce qui permet, sur Android, de continuer à écouter un clip **écran
/// éteint** avec les contrôles dans le volet de notifications — le « mode
/// YouTube Music » décrit dans l'architecture.
class VibeoAudioHandler extends BaseAudioHandler with SeekHandler {
  VibeoAudioHandler() {
    // Rediffuse l'état de `just_audio` vers le système, qui met à jour la
    // notification et les contrôles Bluetooth / écran de verrouillage.
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
  }

  final AudioPlayer _player = AudioPlayer();

  AudioPlayer get player => _player;

  /// Charge une piste et renseigne les métadonnées affichées dans la
  /// notification (titre, artiste, pochette).
  Future<Duration?> setTrack({
    required String id,
    required String url,
    required String title,
    required String artist,
    String? artUri,
    Duration initialPosition = Duration.zero,
  }) async {
    mediaItem.add(
      MediaItem(
        id: id,
        title: title,
        artist: artist,
        artUri: artUri == null ? null : Uri.tryParse(artUri),
      ),
    );
    final duration = await _player.setUrl(url);
    if (initialPosition > Duration.zero) {
      await _player.seek(initialPosition);
    }
    return duration;
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  Future<void> disposePlayer() => _player.dispose();

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.rewind,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.fastForward,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 3],
      processingState: switch (_player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }
}
