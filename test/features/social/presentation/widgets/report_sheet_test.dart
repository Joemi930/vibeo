import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/features/social/data/social_repository.dart';
import 'package:vibeo/features/social/presentation/providers/social_providers.dart';
import 'package:vibeo/features/social/presentation/widgets/report_sheet.dart';

import '../../../../helpers/fake_social_repository.dart';

/// Petit écran hôte : un simple bouton qui ouvre la feuille de signalement,
/// comme le ferait `CommentsSection` ou l'écran du lecteur.
class _HostScreen extends StatelessWidget {
  const _HostScreen({this.videoId, this.commentId});

  final String? videoId;
  final String? commentId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () =>
              showReportSheet(context, videoId: videoId, commentId: commentId),
          child: const Text('Ouvrir'),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() {
    // Évite tout accès réseau aux polices pendant les tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<ProviderContainer> pumpHost(
    WidgetTester tester,
    ThemeData theme, {
    String? videoId = 'video-1',
    String? commentId,
    FakeSocialRepository? socialRepo,
  }) async {
    // La feuille (DraggableScrollableSheet) contient sept motifs, un champ de
    // détails et un bouton : une fenêtre plus haute que la taille de test par
    // défaut évite de devoir faire défiler pour atteindre le bouton d'envoi.
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        socialRepositoryProvider.overrideWithValue(
          socialRepo ?? FakeSocialRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme,
          home: _HostScreen(videoId: videoId, commentId: commentId),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    return container;
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';

    testWidgets('ReportSheet affiche tous les motifs (thème $name)', (
      tester,
    ) async {
      await pumpHost(tester, isDark ? AppTheme.dark : AppTheme.light);

      expect(find.text('Signaler ce clip'), findsOneWidget);
      expect(find.text('Spam ou publicité'), findsOneWidget);
      expect(find.text('Propos haineux'), findsOneWidget);
      expect(find.text('Contenu sexuel'), findsOneWidget);
      expect(find.text('Violence'), findsOneWidget);
      expect(find.text('Atteinte aux droits d\'auteur'), findsOneWidget);
      expect(find.text('Fausse information'), findsOneWidget);
      expect(find.text('Autre'), findsOneWidget);
      expect(find.text('Envoyer le signalement'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'affiche « Signaler ce commentaire » quand commentId est fourni',
    (tester) async {
      await pumpHost(
        tester,
        AppTheme.dark,
        videoId: null,
        commentId: 'comment-1',
      );

      expect(find.text('Signaler ce commentaire'), findsOneWidget);
      expect(find.text('Signaler ce clip'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'envoie le signalement avec le motif choisi et ferme la feuille',
    (tester) async {
      final repo = FakeSocialRepository();
      await pumpHost(tester, AppTheme.light, socialRepo: repo);

      await tester.tap(find.text('Violence'));
      await tester.pump();
      await tester.tap(find.text('Envoyer le signalement'));
      await tester.pumpAndSettle();

      expect(repo.calls, contains('report:video-1:violence'));
      // La feuille est fermée : son contenu n'apparaît plus.
      expect(find.text('Signaler ce clip'), findsNothing);
      expect(
        find.text('Signalement envoyé. Merci pour ta vigilance.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('transmet les détails facultatifs saisis', (tester) async {
    final repo = FakeSocialRepository();
    await pumpHost(tester, AppTheme.dark, socialRepo: repo);

    await tester.enterText(find.byType(TextField), 'Contexte additionnel');
    await tester.tap(find.text('Envoyer le signalement'));
    await tester.pumpAndSettle();

    expect(repo.calls, contains('report:video-1:spam'));
  });

  testWidgets('affiche le message d\'erreur renvoyé par le dépôt', (
    tester,
  ) async {
    final repo = FakeSocialRepository(
      throwOnReport: const SocialException('Tu as déjà signalé ce contenu.'),
    );
    await pumpHost(tester, AppTheme.light, socialRepo: repo);

    await tester.tap(find.text('Envoyer le signalement'));
    await tester.pumpAndSettle();

    expect(find.text('Tu as déjà signalé ce contenu.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
