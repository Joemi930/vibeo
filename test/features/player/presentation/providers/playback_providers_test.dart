import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibeo/features/player/presentation/providers/playback_providers.dart';
import 'package:vibeo/features/video/presentation/providers/video_providers.dart';

import '../../../../helpers/fake_video_repository.dart';

/// Faux dépôt dont `signedVideoUrl` échoue toujours (renvoie `null`), pour
/// simuler l'échec de re-signature qui est la cause première du bouton
/// « Revenir à la vidéo » resté inerte : `switchToVideo` doit alors se
/// terminer proprement plutôt que de laisser `isLoading` bloqué à vrai.
class _FailingSignRepository extends FakeVideoRepository {
  int signCallCount = 0;

  @override
  Future<String?> signedVideoUrl(String? storagePath) async {
    signCallCount++;
    calls.add('signedVideoUrl:$storagePath');
    return null;
  }
}

/// Variante qui retarde sa réponse, pour observer le verrou de ré-entrance :
/// un deuxième appel lancé pendant que le premier est en cours ne doit
/// déclencher aucune tentative supplémentaire.
class _DelayedFailingRepository extends _FailingSignRepository {
  @override
  Future<String?> signedVideoUrl(String? storagePath) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return super.signedVideoUrl(storagePath);
  }
}

void main() {
  group('PlaybackState', () {
    test('copyWith propage engineGeneration', () {
      const initial = PlaybackState(engineGeneration: 3);
      final updated = initial.copyWith(engineGeneration: 4);

      expect(updated.engineGeneration, 4);
      // Sans argument, la valeur précédente doit être conservée.
      expect(initial.copyWith().engineGeneration, 3);
    });

    test('progress se borne à [0, 1]', () {
      const noDuration = PlaybackState();
      expect(noDuration.progress, 0);

      const overshoot = PlaybackState(
        position: Duration(seconds: 90),
        duration: Duration(seconds: 60),
      );
      expect(overshoot.progress, 1);

      const undershoot = PlaybackState(
        position: Duration(seconds: -5),
        duration: Duration(seconds: 60),
      );
      expect(undershoot.progress, 0);

      const half = PlaybackState(
        position: Duration(seconds: 30),
        duration: Duration(seconds: 60),
      );
      expect(half.progress, closeTo(0.5, 0.0001));
    });

    test('hasMedia et isAudioMode reflètent video et mode', () {
      final video = buildTestVideo();
      const empty = PlaybackState();
      expect(empty.hasMedia, isFalse);
      expect(empty.isAudioMode, isFalse);

      final withVideo = PlaybackState(video: video, mode: PlaybackMode.audio);
      expect(withVideo.hasMedia, isTrue);
      expect(withVideo.isAudioMode, isTrue);
    });
  });

  group('PlaybackController.switchToVideo', () {
    late ProviderContainer container;

    tearDown(() => container.dispose());

    test('sans clip chargé, renvoie false sans lever d\'exception', () async {
      container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWithValue(FakeVideoRepository()),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(playbackControllerProvider.notifier);

      final result = await notifier.switchToVideo();

      expect(result, isFalse);
      expect(container.read(playbackControllerProvider).isLoading, isFalse);
    });

    test('quand la re-signature de l\'URL échoue, renvoie false, remet '
        'isLoading à false et publie un errorMessage', () async {
      final repo = _FailingSignRepository();
      container = ProviderContainer(
        overrides: [videoRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(playbackControllerProvider.notifier);
      final video = buildTestVideo();
      // État simulant une lecture audio en cours, sans passer par `open()`
      // (qui toucherait le vrai moteur vidéo, indisponible en test).
      notifier.state = PlaybackState(video: video, mode: PlaybackMode.audio);

      final result = await notifier.switchToVideo();

      expect(result, isFalse);
      final state = container.read(playbackControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, isNotNull);
      expect(repo.calls, contains('signedVideoUrl:${video.videoPath}'));
    });

    test('deux appels concurrents ne déclenchent qu\'une seule tentative '
        '(verrou de ré-entrance)', () async {
      final repo = _DelayedFailingRepository();
      container = ProviderContainer(
        overrides: [videoRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(playbackControllerProvider.notifier);
      final video = buildTestVideo();
      notifier.state = PlaybackState(video: video, mode: PlaybackMode.audio);

      final first = notifier.switchToVideo();
      final second = notifier.switchToVideo();

      final results = await Future.wait([first, second]);

      expect(results, [isFalse, isFalse]);
      expect(repo.signCallCount, 1);
    });
  });
}
