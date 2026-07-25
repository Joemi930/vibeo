import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/core/widgets/subscribe_button.dart';

void main() {
  setUpAll(() {
    // Évite tout accès réseau aux polices pendant les tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpButton(
    WidgetTester tester,
    ThemeData theme, {
    required bool isSubscribed,
    bool isBusy = false,
    VoidCallback? onPressed,
    bool expand = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: SubscribeButton(
              isSubscribed: isSubscribed,
              isBusy: isBusy,
              onPressed: onPressed ?? () {},
              expand: expand,
            ),
          ),
        ),
      ),
    );
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';

    testWidgets('affiche « S\'abonner » quand non abonné (thème $name)', (
      tester,
    ) async {
      await pumpButton(
        tester,
        isDark ? AppTheme.dark : AppTheme.light,
        isSubscribed: false,
      );

      expect(find.text("S'abonner"), findsOneWidget);
      expect(find.text('Abonné'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('affiche « Abonné » quand abonné (thème $name)', (
      tester,
    ) async {
      await pumpButton(
        tester,
        isDark ? AppTheme.dark : AppTheme.light,
        isSubscribed: true,
      );

      expect(find.text('Abonné'), findsOneWidget);
      expect(find.text("S'abonner"), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('déclenche onPressed au tap quand non abonné', (tester) async {
    var tapped = false;
    await pumpButton(
      tester,
      AppTheme.dark,
      isSubscribed: false,
      onPressed: () => tapped = true,
    );

    await tester.tap(find.text("S'abonner"));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('déclenche onPressed au tap quand déjà abonné (désabonnement)', (
    tester,
  ) async {
    var tapped = false;
    await pumpButton(
      tester,
      AppTheme.light,
      isSubscribed: true,
      onPressed: () => tapped = true,
    );

    await tester.tap(find.text('Abonné'));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('ignore le tap quand isBusy est vrai', (tester) async {
    var tapped = false;
    await pumpButton(
      tester,
      AppTheme.dark,
      isSubscribed: false,
      isBusy: true,
      onPressed: () => tapped = true,
    );

    await tester.tap(find.text("S'abonner"), warnIfMissed: false);
    await tester.pump();

    expect(tapped, isFalse);
  });

  testWidgets('expand: true occupe toute la largeur disponible', (
    tester,
  ) async {
    await pumpButton(tester, AppTheme.dark, isSubscribed: false, expand: true);

    final sizedBox = tester.widget<SizedBox>(
      find
          .descendant(
            of: find.byType(SubscribeButton),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(sizedBox.width, double.infinity);
    expect(tester.takeException(), isNull);
  });
}
