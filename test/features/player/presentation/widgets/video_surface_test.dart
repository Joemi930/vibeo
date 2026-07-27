import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/features/player/presentation/providers/playback_providers.dart';
import 'package:vibeo/features/player/presentation/widgets/video_surface.dart';
import 'package:vibeo/features/video/presentation/providers/video_providers.dart';

import '../../../../helpers/fake_video_repository.dart';

/// Faux dépôt dont `signedVideoUrl` échoue toujours : évite de faire tomber
/// le test sur `_startVideo`, qui toucherait un vrai `VideoPlayerController`
/// (aucun greffon plateforme en test unitaire). Seul l'appel importe ici,
/// pas son succès.
class _FailingSignRepository extends FakeVideoRepository {
  @override
  Future<String?> signedVideoUrl(String? storagePath) async {
    calls.add('signedVideoUrl:$storagePath');
    return null;
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';

    testWidgets(
      'en mode audio, le bouton « Revenir à la vidéo » est affiché et '
      'déclenche bien un retour au mode vidéo (thème $name)',
      (tester) async {
        final repo = _FailingSignRepository();
        final video = buildTestVideo();

        final container = ProviderContainer(
          overrides: [videoRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);
        container.read(playbackControllerProvider.notifier).state =
            PlaybackState(video: video, mode: PlaybackMode.audio);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: isDark ? AppTheme.dark : AppTheme.light,
              home: Scaffold(body: VideoSurface(video: video)),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Revenir à la vidéo'), findsOneWidget);

        await tester.tap(find.text('Revenir à la vidéo'));
        // La bascule est asynchrone (re-signature d'URL) : on laisse tourner
        // la boucle d'événements sans attendre un état stable, l'échec de
        // signature étant volontaire ici.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Le bouton a bien déclenché une tentative de bascule côté
        // contrôleur : c'était précisément ce que l'ancien `VoidCallback`
        // n'attendait pas, avalant l'échec en silence.
        expect(repo.calls, contains('signedVideoUrl:${video.videoPath}'));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
