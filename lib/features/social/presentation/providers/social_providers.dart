import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/dev_log.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../video/domain/artist_summary.dart';
import '../../data/social_repository.dart';
import '../../domain/comment.dart';
import '../../domain/report_reason.dart';

final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  return SupabaseSocialRepository(ref.watch(supabaseClientProvider));
});

// ---------------------------------------------------------------------------
// Likes
// ---------------------------------------------------------------------------

/// État local du bouton « j'aime ».
///
/// [delta] est l'écart à appliquer au compteur venu du serveur, plutôt qu'un
/// total recopié : l'affichage reste juste sans avoir à recharger le clip, et
/// un échec se corrige en remettant simplement l'écart à zéro.
@immutable
class LikeState {
  const LikeState({this.isLiked = false, this.delta = 0, this.isBusy = false});

  final bool isLiked;
  final int delta;
  final bool isBusy;

  LikeState copyWith({bool? isLiked, int? delta, bool? isBusy}) => LikeState(
    isLiked: isLiked ?? this.isLiked,
    delta: delta ?? this.delta,
    isBusy: isBusy ?? this.isBusy,
  );
}

/// Bouton « j'aime » d'un clip, en affichage optimiste.
///
/// L'état bascule immédiatement, puis est corrigé si le serveur refuse. Un
/// second appui ne double jamais le compteur : la clé primaire
/// `(video_id, user_id)` l'empêche côté base.
class LikeController extends Notifier<LikeState> {
  LikeController(this.videoId);

  final String videoId;

  @override
  LikeState build() {
    _loadInitial();
    return const LikeState();
  }

  Future<void> _loadInitial() async {
    try {
      final liked = await ref.read(socialRepositoryProvider).isLiked(videoId);
      if (liked) state = state.copyWith(isLiked: true);
    } catch (error) {
      logError('état du like indisponible', error);
    }
  }

  Future<void> toggle() async {
    if (state.isBusy) return;
    final wasLiked = state.isLiked;
    final previousDelta = state.delta;

    state = state.copyWith(
      isLiked: !wasLiked,
      delta: previousDelta + (wasLiked ? -1 : 1),
      isBusy: true,
    );

    try {
      final repo = ref.read(socialRepositoryProvider);
      if (wasLiked) {
        await repo.unlike(videoId);
      } else {
        await repo.like(videoId);
      }
      state = state.copyWith(isBusy: false);
    } catch (error) {
      logError('like impossible', error);
      state = LikeState(isLiked: wasLiked, delta: previousDelta);
    }
  }
}

final likeControllerProvider =
    NotifierProvider.family<LikeController, LikeState, String>(
      LikeController.new,
    );

// ---------------------------------------------------------------------------
// Abonnements
// ---------------------------------------------------------------------------

@immutable
class SubscribeState {
  const SubscribeState({
    this.isSubscribed = false,
    this.delta = 0,
    this.isBusy = false,
  });

  final bool isSubscribed;
  final int delta;
  final bool isBusy;

  SubscribeState copyWith({bool? isSubscribed, int? delta, bool? isBusy}) =>
      SubscribeState(
        isSubscribed: isSubscribed ?? this.isSubscribed,
        delta: delta ?? this.delta,
        isBusy: isBusy ?? this.isBusy,
      );
}

/// Bouton « S'abonner », même principe optimiste que [LikeController].
class SubscribeController extends Notifier<SubscribeState> {
  SubscribeController(this.artistId);

  final String artistId;

  @override
  SubscribeState build() {
    _loadInitial();
    return const SubscribeState();
  }

  Future<void> _loadInitial() async {
    try {
      final subscribed = await ref
          .read(socialRepositoryProvider)
          .isSubscribed(artistId);
      if (subscribed) state = state.copyWith(isSubscribed: true);
    } catch (error) {
      logError('état d\'abonnement indisponible', error);
    }
  }

  Future<void> toggle() async {
    if (state.isBusy) return;
    final wasSubscribed = state.isSubscribed;
    final previousDelta = state.delta;

    state = state.copyWith(
      isSubscribed: !wasSubscribed,
      delta: previousDelta + (wasSubscribed ? -1 : 1),
      isBusy: true,
    );

    try {
      final repo = ref.read(socialRepositoryProvider);
      if (wasSubscribed) {
        await repo.unsubscribe(artistId);
      } else {
        await repo.subscribe(artistId);
      }
      ref.invalidate(subscriptionsProvider);
      state = state.copyWith(isBusy: false);
    } catch (error) {
      logError('abonnement impossible', error);
      state = SubscribeState(isSubscribed: wasSubscribed, delta: previousDelta);
    }
  }
}

final subscribeControllerProvider =
    NotifierProvider.family<SubscribeController, SubscribeState, String>(
      SubscribeController.new,
    );

/// Artistes suivis par l'utilisateur courant (onglet Abonnements).
final subscriptionsProvider = FutureProvider<List<ArtistSummary>>((ref) {
  return ref.watch(socialRepositoryProvider).fetchSubscriptions();
});

// ---------------------------------------------------------------------------
// Commentaires
// ---------------------------------------------------------------------------

/// Fil de commentaires paginé d'un clip.
@immutable
class CommentsState {
  const CommentsState({
    this.comments = const [],
    this.isLoadingMore = false,
    this.hasMore = true,
    this.errorMessage,
  });

  final List<Comment> comments;
  final bool isLoadingMore;
  final bool hasMore;
  final String? errorMessage;

  CommentsState copyWith({
    List<Comment>? comments,
    bool? isLoadingMore,
    bool? hasMore,
    String? errorMessage,
    bool clearError = false,
  }) => CommentsState(
    comments: comments ?? this.comments,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMore: hasMore ?? this.hasMore,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
  );
}

class CommentsController extends AsyncNotifier<CommentsState> {
  CommentsController(this.videoId);

  final String videoId;

  static const int _pageSize = 20;

  @override
  Future<CommentsState> build() async {
    final page = await ref
        .read(socialRepositoryProvider)
        .fetchComments(videoId, limit: _pageSize);
    return CommentsState(comments: page, hasMore: page.length == _pageSize);
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true, clearError: true));
    try {
      final page = await ref
          .read(socialRepositoryProvider)
          .fetchComments(
            videoId,
            limit: _pageSize,
            offset: current.comments.length,
          );
      state = AsyncData(
        current.copyWith(
          comments: [...current.comments, ...page],
          isLoadingMore: false,
          hasMore: page.length == _pageSize,
        ),
      );
    } catch (error) {
      logError('pagination des commentaires impossible', error);
      state = AsyncData(
        current.copyWith(
          isLoadingMore: false,
          errorMessage: 'Impossible de charger la suite.',
        ),
      );
    }
  }

  /// Ajoute un commentaire et le place en tête du fil.
  ///
  /// Renvoie `null` en cas de succès, sinon le message d'erreur à afficher.
  Future<String?> add(String body) async {
    final current = state.asData?.value;
    if (current == null) return 'Réessaie dans un instant.';

    try {
      final comment = await ref
          .read(socialRepositoryProvider)
          .addComment(videoId: videoId, body: body);
      state = AsyncData(
        current.copyWith(
          comments: [comment, ...current.comments],
          clearError: true,
        ),
      );
      return null;
    } on SocialException catch (e) {
      return e.message;
    } catch (error) {
      logError('commentaire impossible', error);
      return 'L\'envoi du commentaire a échoué. Réessaie.';
    }
  }

  /// Supprime un commentaire. Le serveur refuse si ce n'est pas le sien.
  Future<String?> remove(String commentId) async {
    final current = state.asData?.value;
    if (current == null) return null;

    final previous = current.comments;
    state = AsyncData(
      current.copyWith(
        comments: previous.where((c) => c.id != commentId).toList(),
      ),
    );

    try {
      await ref.read(socialRepositoryProvider).deleteComment(commentId);
      return null;
    } catch (error) {
      logError('suppression du commentaire impossible', error);
      state = AsyncData(current.copyWith(comments: previous));
      return 'La suppression a échoué.';
    }
  }
}

final commentsControllerProvider =
    AsyncNotifierProvider.family<CommentsController, CommentsState, String>(
      CommentsController.new,
    );

// ---------------------------------------------------------------------------
// Signalements
// ---------------------------------------------------------------------------

/// Envoie un signalement. Renvoie `null` si tout s'est bien passé, sinon le
/// message d'erreur à afficher.
Future<String?> submitReport(
  Ref ref, {
  String? videoId,
  String? commentId,
  required ReportReason reason,
  String? details,
}) async {
  try {
    await ref
        .read(socialRepositoryProvider)
        .report(
          videoId: videoId,
          commentId: commentId,
          reason: reason,
          details: details,
        );
    return null;
  } on SocialException catch (e) {
    return e.message;
  } catch (error) {
    logError('signalement impossible', error);
    return 'L\'envoi du signalement a échoué. Réessaie.';
  }
}
