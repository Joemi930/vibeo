import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibeo/features/auth/domain/user_role.dart';
import 'package:vibeo/features/social/data/social_repository.dart';
import 'package:vibeo/features/social/domain/comment.dart';
import 'package:vibeo/features/social/presentation/providers/social_providers.dart';
import 'package:vibeo/features/video/domain/artist_summary.dart';

import '../../../../helpers/fake_social_repository.dart';

void main() {
  ProviderContainer makeContainer(FakeSocialRepository repo) {
    final container = ProviderContainer(
      overrides: [socialRepositoryProvider.overrideWithValue(repo)],
      retry: (retryCount, error) => null,
    );
    return container;
  }

  group('LikeController', () {
    test('charge l\'état initial « liké » depuis le dépôt', () async {
      final repo = FakeSocialRepository(likedVideoIds: {'video-1'});
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      container.read(likeControllerProvider('video-1')); // déclenche build()
      await Future<void>.delayed(Duration.zero);

      expect(container.read(likeControllerProvider('video-1')).isLiked, isTrue);
    });

    test('toggle() bascule en optimiste puis confirme (delta +1)', () async {
      final repo = FakeSocialRepository();
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await Future<void>.delayed(Duration.zero);

      await container.read(likeControllerProvider('video-1').notifier).toggle();

      final state = container.read(likeControllerProvider('video-1'));
      expect(state.isLiked, isTrue);
      expect(state.delta, 1);
      expect(state.isBusy, isFalse);
      expect(repo.calls, contains('like:video-1'));
    });

    test('un aller-retour like/unlike ramène le delta à zéro', () async {
      final repo = FakeSocialRepository();
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await Future<void>.delayed(Duration.zero);

      final notifier = container.read(
        likeControllerProvider('video-1').notifier,
      );
      await notifier.toggle();
      await notifier.toggle();

      final state = container.read(likeControllerProvider('video-1'));
      expect(state.isLiked, isFalse);
      expect(state.delta, 0);
      expect(
        repo.calls,
        containsAllInOrder(['like:video-1', 'unlike:video-1']),
      );
    });

    test(
      'un échec serveur restaure l\'état précédent (delta annulé)',
      () async {
        final repo = FakeSocialRepository(throwOnLike: true);
        final container = makeContainer(repo);
        addTearDown(container.dispose);
        await Future<void>.delayed(Duration.zero);

        await container
            .read(likeControllerProvider('video-1').notifier)
            .toggle();

        final state = container.read(likeControllerProvider('video-1'));
        expect(state.isLiked, isFalse);
        expect(state.delta, 0);
        expect(state.isBusy, isFalse);
      },
    );
  });

  group('SubscribeController', () {
    test('charge l\'état initial « abonné » depuis le dépôt', () async {
      final repo = FakeSocialRepository(subscribedArtistIds: {'artist-1'});
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      container.read(subscribeControllerProvider('artist-1'));
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(subscribeControllerProvider('artist-1')).isSubscribed,
        isTrue,
      );
    });

    test('toggle() bascule en optimiste puis confirme (delta +1)', () async {
      final repo = FakeSocialRepository();
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await Future<void>.delayed(Duration.zero);

      await container
          .read(subscribeControllerProvider('artist-1').notifier)
          .toggle();

      final state = container.read(subscribeControllerProvider('artist-1'));
      expect(state.isSubscribed, isTrue);
      expect(state.delta, 1);
      expect(repo.calls, contains('subscribe:artist-1'));
    });

    test(
      'un échec serveur restaure l\'état précédent (delta annulé)',
      () async {
        final repo = FakeSocialRepository(throwOnSubscribe: true);
        final container = makeContainer(repo);
        addTearDown(container.dispose);
        await Future<void>.delayed(Duration.zero);

        await container
            .read(subscribeControllerProvider('artist-1').notifier)
            .toggle();

        final state = container.read(subscribeControllerProvider('artist-1'));
        expect(state.isSubscribed, isFalse);
        expect(state.delta, 0);
      },
    );

    test('un abonnement réussi invalide la liste des abonnements', () async {
      const artist = ArtistSummary(
        id: 'artist-1',
        username: 'naika',
        role: UserRole.artist,
      );
      final repo = FakeSocialRepository(subscriptions: [artist]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      // Première lecture : une résolution.
      await container.read(subscriptionsProvider.future);
      expect(repo.calls.where((c) => c == 'fetchSubscriptions').length, 1);

      await container
          .read(subscribeControllerProvider('artist-1').notifier)
          .toggle();

      // La resollicitation après invalidation déclenche un second appel.
      await container.read(subscriptionsProvider.future);
      expect(repo.calls.where((c) => c == 'fetchSubscriptions').length, 2);
    });
  });

  group('CommentsController', () {
    List<Comment> buildComments(String videoId, int count) => List.generate(
      count,
      (i) => Comment(
        id: 'comment-$i',
        videoId: videoId,
        authorId: 'user-1',
        body: 'Commentaire $i',
        createdAt: DateTime(2026, 7, 25),
      ),
    );

    test(
      'build() charge la première page et détecte s\'il reste des pages',
      () async {
        final repo = FakeSocialRepository(
          comments: buildComments('video-1', 25),
        );
        final container = makeContainer(repo);
        addTearDown(container.dispose);

        final state = await container.read(
          commentsControllerProvider('video-1').future,
        );

        expect(state.comments, hasLength(20));
        expect(state.hasMore, isTrue);
      },
    );

    test(
      'build() indique hasMore=false quand la page n\'est pas pleine',
      () async {
        final repo = FakeSocialRepository(
          comments: buildComments('video-1', 5),
        );
        final container = makeContainer(repo);
        addTearDown(container.dispose);

        final state = await container.read(
          commentsControllerProvider('video-1').future,
        );

        expect(state.comments, hasLength(5));
        expect(state.hasMore, isFalse);
      },
    );

    test('loadMore() ajoute la suite et met à jour hasMore', () async {
      final repo = FakeSocialRepository(comments: buildComments('video-1', 25));
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(commentsControllerProvider('video-1').future);

      await container
          .read(commentsControllerProvider('video-1').notifier)
          .loadMore();

      final state = container
          .read(commentsControllerProvider('video-1'))
          .asData!
          .value;
      expect(state.comments, hasLength(25));
      expect(state.hasMore, isFalse);
      expect(state.isLoadingMore, isFalse);
    });

    test('add() place le nouveau commentaire en tête du fil', () async {
      final repo = FakeSocialRepository(comments: buildComments('video-1', 2));
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(commentsControllerProvider('video-1').future);

      final error = await container
          .read(commentsControllerProvider('video-1').notifier)
          .add('Un nouveau commentaire');

      expect(error, isNull);
      final state = container
          .read(commentsControllerProvider('video-1'))
          .asData!
          .value;
      expect(state.comments, hasLength(3));
      expect(state.comments.first.body, 'Un nouveau commentaire');
    });

    test(
      'add() renvoie le message d\'erreur métier sans modifier l\'état',
      () async {
        final repo = FakeSocialRepository(
          comments: buildComments('video-1', 1),
          throwOnAddComment: const SocialException(
            'Tu as atteint la limite de 30 commentaires par heure.',
          ),
        );
        final container = makeContainer(repo);
        addTearDown(container.dispose);
        await container.read(commentsControllerProvider('video-1').future);

        final error = await container
            .read(commentsControllerProvider('video-1').notifier)
            .add('Un commentaire de trop');

        expect(error, 'Tu as atteint la limite de 30 commentaires par heure.');
        final state = container
            .read(commentsControllerProvider('video-1'))
            .asData!
            .value;
        expect(state.comments, hasLength(1));
      },
    );

    test('remove() retire le commentaire de façon optimiste', () async {
      final repo = FakeSocialRepository(comments: buildComments('video-1', 3));
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(commentsControllerProvider('video-1').future);

      final error = await container
          .read(commentsControllerProvider('video-1').notifier)
          .remove('comment-1');

      expect(error, isNull);
      final state = container
          .read(commentsControllerProvider('video-1'))
          .asData!
          .value;
      expect(state.comments.map((c) => c.id), isNot(contains('comment-1')));
      expect(state.comments, hasLength(2));
    });

    test(
      'remove() restaure la liste précédente en cas d\'échec serveur',
      () async {
        final repo = FakeSocialRepository(
          comments: buildComments('video-1', 3),
          throwOnDeleteComment: true,
        );
        final container = makeContainer(repo);
        addTearDown(container.dispose);
        await container.read(commentsControllerProvider('video-1').future);

        final error = await container
            .read(commentsControllerProvider('video-1').notifier)
            .remove('comment-1');

        expect(error, 'La suppression a échoué.');
        final state = container
            .read(commentsControllerProvider('video-1'))
            .asData!
            .value;
        expect(state.comments.map((c) => c.id), contains('comment-1'));
        expect(state.comments, hasLength(3));
      },
    );
  });
}
