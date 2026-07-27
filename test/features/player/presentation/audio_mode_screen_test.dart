import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vibeo/core/router/app_routes.dart';
import 'package:vibeo/features/player/presentation/audio_mode_screen.dart';
import 'package:vibeo/features/player/presentation/providers/playback_providers.dart';
import 'package:vibeo/features/video/presentation/providers/video_providers.dart';

import '../../../helpers/fake_video_repository.dart';

/// Vérifie la régression la plus importante du correctif : sur le web, un
/// lien direct ou un rechargement de page laisse une pile de navigation à une
/// seule route (`canPop() == false`). `returnToVideo` doit alors atterrir sur
/// le lecteur du clip, jamais sur l'accueil — c'était le repli implicite
/// avant correctif.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'returnToVideo rejoint /video/<id> sans repasser par l\'accueil, même '
    'sans pile à dépiler',
    (tester) async {
      final router = GoRouter(
        initialLocation: AppRoutes.audio('video-1'),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const Scaffold(body: Text('ACCUEIL')),
          ),
          GoRoute(
            path: AppRoutes.audioPattern,
            builder: (context, state) {
              final videoId = state.pathParameters['videoId']!;
              return Consumer(
                builder: (context, ref, _) {
                  final controller = ref.read(
                    playbackControllerProvider.notifier,
                  );
                  return Scaffold(
                    body: ElevatedButton(
                      onPressed: () =>
                          returnToVideo(context, controller, videoId),
                      child: const Text('Revenir à la vidéo'),
                    ),
                  );
                },
              );
            },
          ),
          GoRoute(
            path: AppRoutes.videoPattern,
            builder: (context, state) => Scaffold(
              body: Text('LECTEUR ${state.pathParameters['videoId']}'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            videoRepositoryProvider.overrideWithValue(FakeVideoRepository()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Pile de navigation d'une seule route : rien à dépiler.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isFalse);

      await tester.tap(find.text('Revenir à la vidéo'));
      await tester.pumpAndSettle();

      expect(find.text('LECTEUR video-1'), findsOneWidget);
      expect(find.text('ACCUEIL'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
