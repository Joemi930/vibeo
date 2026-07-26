import 'package:vibeo/features/social/data/social_repository.dart';
import 'package:vibeo/features/social/domain/comment.dart';
import 'package:vibeo/features/social/domain/report_reason.dart';
import 'package:vibeo/features/video/domain/artist_summary.dart';

/// Faux dépôt social, écrit à la main (convention du projet : ni mockito, ni
/// génération de code). Journalise les appels et permet d'injecter des
/// erreurs, sur le modèle de `FakeVideoRepository` / `FakePlaylistRepository`.
class FakeSocialRepository implements SocialRepository {
  FakeSocialRepository({
    List<ArtistSummary> subscriptions = const [],
    this.throwOnFetch = false,
    Set<String> likedVideoIds = const {},
    Set<String> subscribedArtistIds = const {},
    List<Comment> comments = const [],
    this.throwOnLike = false,
    this.throwOnSubscribe = false,
    this.throwOnAddComment,
    this.throwOnDeleteComment = false,
    this.throwOnReport,
  }) : subscriptions = [...subscriptions],
       likedVideoIds = {...likedVideoIds},
       subscribedArtistIds = {...subscribedArtistIds},
       comments = [...comments];

  List<ArtistSummary> subscriptions;
  bool throwOnFetch;

  Set<String> likedVideoIds;
  Set<String> subscribedArtistIds;
  List<Comment> comments;

  bool throwOnLike;
  bool throwOnSubscribe;

  /// Si non nulle, `addComment` lève cette exception (ex. limite de débit).
  SocialException? throwOnAddComment;
  bool throwOnDeleteComment;

  /// Si non nulle, `report` lève cette exception (ex. déjà signalé).
  SocialException? throwOnReport;

  final List<String> calls = [];

  @override
  Future<bool> isLiked(String videoId) async {
    calls.add('isLiked:$videoId');
    if (throwOnFetch) throw Exception('échec réseau simulé');
    return likedVideoIds.contains(videoId);
  }

  @override
  Future<void> like(String videoId) async {
    calls.add('like:$videoId');
    if (throwOnLike) throw Exception('échec réseau simulé');
    likedVideoIds = {...likedVideoIds, videoId};
  }

  @override
  Future<void> unlike(String videoId) async {
    calls.add('unlike:$videoId');
    if (throwOnLike) throw Exception('échec réseau simulé');
    likedVideoIds = {...likedVideoIds}..remove(videoId);
  }

  @override
  Future<List<Comment>> fetchComments(
    String videoId, {
    int limit = 20,
    int offset = 0,
  }) async {
    calls.add('fetchComments:$videoId:$limit:$offset');
    if (throwOnFetch) throw Exception('échec réseau simulé');
    // Même contrat que SupabaseSocialRepository : pagination sur les
    // commentaires racine, réponses rattachées ensuite sans pagination.
    final roots = comments
        .where((c) => c.videoId == videoId && !c.isReply)
        .toList();
    if (offset >= roots.length) return const [];
    final end = (offset + limit).clamp(0, roots.length);
    final page = roots.sublist(offset, end);

    return page
        .map(
          (root) => root.copyWith(
            replies: comments.where((c) => c.parentId == root.id).toList(),
          ),
        )
        .toList();
  }

  @override
  Future<Comment> addComment({
    required String videoId,
    required String body,
    String? parentId,
  }) async {
    calls.add('addComment:$videoId');
    if (throwOnAddComment != null) throw throwOnAddComment!;
    final comment = Comment(
      id: 'comment-${comments.length + 1}',
      videoId: videoId,
      authorId: 'user-1',
      body: body,
      createdAt: DateTime(2026, 7, 25),
      parentId: parentId,
    );
    comments = [comment, ...comments];
    return comment;
  }

  @override
  Future<void> deleteComment(String commentId) async {
    calls.add('deleteComment:$commentId');
    if (throwOnDeleteComment) throw Exception('échec réseau simulé');
    comments = comments.where((c) => c.id != commentId).toList();
  }

  @override
  Future<bool> isSubscribed(String artistId) async {
    calls.add('isSubscribed:$artistId');
    if (throwOnFetch) throw Exception('échec réseau simulé');
    return subscribedArtistIds.contains(artistId);
  }

  @override
  Future<void> subscribe(String artistId) async {
    calls.add('subscribe:$artistId');
    if (throwOnSubscribe) throw Exception('échec réseau simulé');
    subscribedArtistIds = {...subscribedArtistIds, artistId};
  }

  @override
  Future<void> unsubscribe(String artistId) async {
    calls.add('unsubscribe:$artistId');
    if (throwOnSubscribe) throw Exception('échec réseau simulé');
    subscribedArtistIds = {...subscribedArtistIds}..remove(artistId);
  }

  @override
  Future<List<ArtistSummary>> fetchSubscriptions() async {
    calls.add('fetchSubscriptions');
    if (throwOnFetch) throw Exception('échec réseau simulé');
    return subscriptions;
  }

  @override
  Future<void> report({
    String? videoId,
    String? commentId,
    required ReportReason reason,
    String? details,
  }) async {
    calls.add('report:${videoId ?? commentId}:${reason.value}');
    if (throwOnReport != null) throw throwOnReport!;
  }
}
