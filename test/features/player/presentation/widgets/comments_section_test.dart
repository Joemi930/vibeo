import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeo/core/theme/app_theme.dart';
import 'package:vibeo/features/auth/domain/profile.dart';
import 'package:vibeo/features/auth/domain/user_role.dart';
import 'package:vibeo/features/auth/presentation/providers/auth_providers.dart';
import 'package:vibeo/features/player/presentation/widgets/comments_section.dart';
import 'package:vibeo/features/profile/presentation/providers/profile_providers.dart';
import 'package:vibeo/features/social/domain/comment.dart';
import 'package:vibeo/features/social/data/social_repository.dart';
import 'package:vibeo/features/social/presentation/providers/social_providers.dart';
import 'package:vibeo/features/video/domain/artist_summary.dart';

import '../../../../helpers/fake_auth_repository.dart';
import '../../../../helpers/fake_social_repository.dart';

/// Utilisateur factice pour simuler un compte connecté (la garde `requireAuth`
/// de `_send` exige une session, voir `require_auth.dart`).
final _fakeUser = User(
  id: 'user-1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime(2026, 1, 1).toIso8601String(),
);

void main() {
  setUpAll(() {
    // Évite tout accès réseau aux polices pendant les tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Comment buildComment({
    String id = 'comment-1',
    String authorId = 'user-2',
    String body = 'Superbe clip !',
    ArtistSummary? author,
  }) => Comment(
    id: id,
    videoId: 'video-1',
    authorId: authorId,
    body: body,
    createdAt: DateTime(2026, 7, 24, 10),
    author:
        author ??
        ArtistSummary(
          id: authorId,
          username: 'fan_$authorId',
          role: UserRole.listener,
        ),
  );

  Future<ProviderContainer> pumpComments(
    WidgetTester tester,
    ThemeData theme, {
    FakeSocialRepository? socialRepo,
    Profile? profile,
    bool authenticated = true,
  }) async {
    final authRepo = FakeAuthRepository(
      initialUser: authenticated ? _fakeUser : null,
    );
    addTearDown(authRepo.dispose);

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        socialRepositoryProvider.overrideWithValue(
          socialRepo ?? FakeSocialRepository(),
        ),
        currentProfileProvider.overrideWith((ref) => profile),
        avatarSignedUrlProvider.overrideWith((ref, path) => null),
      ],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: const CommentsSection(videoId: 'video-1'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  for (final isDark in [true, false]) {
    final name = isDark ? 'sombre' : 'clair';

    testWidgets(
      'CommentsSection affiche le fil de commentaires (thème $name)',
      (tester) async {
        final repo = FakeSocialRepository(
          comments: [
            buildComment(id: 'c1', body: 'Premier commentaire'),
            buildComment(id: 'c2', body: 'Deuxième commentaire'),
          ],
        );
        await pumpComments(
          tester,
          isDark ? AppTheme.dark : AppTheme.light,
          socialRepo: repo,
        );

        expect(find.text('Commentaires'), findsOneWidget);
        expect(find.text('Premier commentaire'), findsOneWidget);
        expect(find.text('Deuxième commentaire'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('affiche un état vide sans commentaire', (tester) async {
    await pumpComments(tester, AppTheme.dark);

    expect(find.text('Aucun commentaire'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('propose « Supprimer » sur son propre commentaire', (
    tester,
  ) async {
    final repo = FakeSocialRepository(
      comments: [buildComment(id: 'c1', authorId: 'user-1')],
    );
    await pumpComments(
      tester,
      AppTheme.dark,
      socialRepo: repo,
      profile: Profile(
        id: 'user-1',
        username: 'moi',
        role: UserRole.listener,
        createdAt: DateTime(2026, 1, 1),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Supprimer'), findsOneWidget);
    expect(find.text('Signaler'), findsNothing);
  });

  testWidgets('propose « Signaler » sur le commentaire d\'autrui', (
    tester,
  ) async {
    final repo = FakeSocialRepository(
      comments: [buildComment(id: 'c1', authorId: 'user-2')],
    );
    await pumpComments(
      tester,
      AppTheme.dark,
      socialRepo: repo,
      profile: Profile(
        id: 'user-1',
        username: 'moi',
        role: UserRole.listener,
        createdAt: DateTime(2026, 1, 1),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Signaler'), findsOneWidget);
    expect(find.text('Supprimer'), findsNothing);
  });

  testWidgets('envoie un commentaire et vide le champ de saisie', (
    tester,
  ) async {
    final repo = FakeSocialRepository(comments: []);
    await pumpComments(tester, AppTheme.light, socialRepo: repo);

    await tester.enterText(find.byType(TextField), 'Mon avis sur ce clip');
    await tester.tap(find.bySemanticsLabel('Envoyer le commentaire'));
    await tester.pumpAndSettle();

    expect(repo.calls, contains('addComment:video-1'));
    expect(find.text('Mon avis sur ce clip'), findsOneWidget);
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  // Le champ de saisie reste visible pour un invité : on peut donc atteindre
  // l'envoi en ayant simplement fait défiler jusqu'au fil, sans passer par la
  // pilule « Commenter » qui porte sa propre garde. Un audit de sécurité a
  // relevé ce chemin non gardé — ce test empêche sa réapparition.
  testWidgets('un invité reçoit l\'invitation à se connecter, sans envoi', (
    tester,
  ) async {
    final repo = FakeSocialRepository(comments: []);
    await pumpComments(
      tester,
      AppTheme.light,
      socialRepo: repo,
      authenticated: false,
    );

    await tester.enterText(find.byType(TextField), 'Commentaire d\'un invité');
    await tester.tap(find.bySemanticsLabel('Envoyer le commentaire'));
    await tester.pumpAndSettle();

    expect(find.text('Connecte-toi pour commenter'), findsOneWidget);
    expect(repo.calls, isNot(contains('addComment:video-1')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('un invité ne peut pas ouvrir la feuille de signalement', (
    tester,
  ) async {
    final repo = FakeSocialRepository(comments: [buildComment(id: 'c1')]);
    await pumpComments(
      tester,
      AppTheme.dark,
      socialRepo: repo,
      authenticated: false,
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Signaler'));
    await tester.pumpAndSettle();

    expect(find.text('Connecte-toi pour signaler ce contenu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('affiche l\'erreur métier au lieu d\'ajouter le commentaire', (
    tester,
  ) async {
    final repo = FakeSocialRepository(
      throwOnAddComment: const SocialException(
        'Tu as atteint la limite de 30 commentaires par heure.',
      ),
    );
    await pumpComments(tester, AppTheme.dark, socialRepo: repo);

    await tester.enterText(find.byType(TextField), 'Un commentaire de trop');
    await tester.tap(find.bySemanticsLabel('Envoyer le commentaire'));
    await tester.pumpAndSettle();

    expect(
      find.text('Tu as atteint la limite de 30 commentaires par heure.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('supprime le commentaire après confirmation', (tester) async {
    final repo = FakeSocialRepository(
      comments: [buildComment(id: 'c1', authorId: 'user-1', body: 'À retirer')],
    );
    await pumpComments(
      tester,
      AppTheme.light,
      socialRepo: repo,
      profile: Profile(
        id: 'user-1',
        username: 'moi',
        role: UserRole.listener,
        createdAt: DateTime(2026, 1, 1),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();

    // Boîte de confirmation.
    expect(find.text('Supprimer ce commentaire ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();

    expect(repo.calls, contains('deleteComment:c1'));
    expect(find.text('À retirer'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('une réponse s\'affiche sous son commentaire parent', (
    tester,
  ) async {
    final repo = FakeSocialRepository(
      comments: [
        buildComment(id: 'c1', body: 'Commentaire racine'),
        Comment(
          id: 'c2',
          videoId: 'video-1',
          authorId: 'user-2',
          body: 'Une réponse au premier commentaire',
          createdAt: DateTime(2026, 7, 24, 11),
          parentId: 'c1',
        ),
      ],
    );
    await pumpComments(tester, AppTheme.light, socialRepo: repo);

    expect(find.text('Commentaire racine'), findsOneWidget);
    // Repliée par défaut : le corps de la réponse n'est pas encore visible.
    expect(find.text('Une réponse au premier commentaire'), findsNothing);
    expect(find.text('1 réponse'), findsOneWidget);

    await tester.tap(find.text('1 réponse'));
    await tester.pumpAndSettle();

    expect(find.text('Une réponse au premier commentaire'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aucun bouton « Répondre » sur une réponse', (tester) async {
    final repo = FakeSocialRepository(
      comments: [
        buildComment(id: 'c1', body: 'Commentaire racine'),
        Comment(
          id: 'c2',
          videoId: 'video-1',
          authorId: 'user-2',
          body: 'Une réponse',
          createdAt: DateTime(2026, 7, 24, 11),
          parentId: 'c1',
        ),
      ],
    );
    await pumpComments(tester, AppTheme.dark, socialRepo: repo);

    await tester.tap(find.text('1 réponse'));
    await tester.pumpAndSettle();

    // Un seul bouton « Répondre », celui de la racine.
    expect(find.text('Répondre'), findsOneWidget);
  });

  testWidgets('envoie une réponse rattachée à sa racine', (tester) async {
    final repo = FakeSocialRepository(
      comments: [buildComment(id: 'c1', body: 'Commentaire racine')],
    );
    await pumpComments(tester, AppTheme.light, socialRepo: repo);

    await tester.tap(find.text('Répondre'));
    await tester.pumpAndSettle();

    // Le champ de réponse apparaît dans l'arbre AVANT le champ racine (imbriqué
    // dans la liste des commentaires, elle-même avant `_CommentInput`) : `.first`.
    await tester.enterText(find.byType(TextField).first, 'Ma réponse');
    await tester.tap(find.bySemanticsLabel('Envoyer la réponse'));
    await tester.pumpAndSettle();

    expect(repo.calls, contains('addComment:video-1'));
    expect(find.text('Ma réponse'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'un invité qui tente de répondre est invité à se connecter, sans envoi',
    (tester) async {
      final repo = FakeSocialRepository(
        comments: [buildComment(id: 'c1', body: 'Commentaire racine')],
      );
      await pumpComments(
        tester,
        AppTheme.light,
        socialRepo: repo,
        authenticated: false,
      );

      await tester.tap(find.text('Répondre'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'Réponse d\'un invité',
      );
      await tester.tap(find.bySemanticsLabel('Envoyer la réponse'));
      await tester.pumpAndSettle();

      expect(find.text('Connecte-toi pour commenter'), findsOneWidget);
      expect(repo.calls, isNot(contains('addComment:video-1')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('annuler la confirmation conserve le commentaire', (
    tester,
  ) async {
    final repo = FakeSocialRepository(
      comments: [buildComment(id: 'c1', authorId: 'user-1', body: 'Je reste')],
    );
    await pumpComments(
      tester,
      AppTheme.dark,
      socialRepo: repo,
      profile: Profile(
        id: 'user-1',
        username: 'moi',
        role: UserRole.listener,
        createdAt: DateTime(2026, 1, 1),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(repo.calls.any((c) => c.startsWith('deleteComment')), isFalse);
    expect(find.text('Je reste'), findsOneWidget);
  });
}
