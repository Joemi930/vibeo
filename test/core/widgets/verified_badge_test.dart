import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/core/widgets/verified_badge.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpUnder(
    WidgetTester tester,
    ThemeData theme,
    Widget child,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pump();
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';
    testWidgets('VerifiedBadge se rend en thème $name', (tester) async {
      await pumpUnder(
        tester,
        isDark ? AppTheme.dark : AppTheme.light,
        const VerifiedBadge(),
      );

      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ArtistNameLabel affiche l\'insigne quand isVerified est true', (
    tester,
  ) async {
    await pumpUnder(
      tester,
      AppTheme.dark,
      const ArtistNameLabel(name: 'Artiste Un', isVerified: true),
    );

    expect(find.text('Artiste Un'), findsOneWidget);
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
  });

  testWidgets(
    'ArtistNameLabel n\'affiche pas l\'insigne quand isVerified est false',
    (tester) async {
      await pumpUnder(
        tester,
        AppTheme.dark,
        const ArtistNameLabel(name: 'Auditeur Deux', isVerified: false),
      );

      expect(find.text('Auditeur Deux'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsNothing);
    },
  );

  testWidgets(
    'ArtistNameLabel tronque un nom très long sans provoquer de débordement',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpUnder(
        tester,
        AppTheme.light,
        const SizedBox(
          width: 150,
          child: ArtistNameLabel(
            name:
                'Un nom d\'artiste extrêmement long destiné à vérifier que '
                'le texte se tronque proprement',
            isVerified: true,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    },
  );
}
