import 'package:supabase_flutter/supabase_flutter.dart';

import '../../video/domain/artist_summary.dart';
import '../domain/comment.dart';
import '../domain/report_reason.dart';

/// Contrat des interactions sociales : likes, commentaires, abonnements,
/// signalements.
///
/// Aucune méthode ne touche aux compteurs : `like_count`, `comment_count` et
/// `subscriber_count` sont maintenus par des triggers SQL (règle n°6 de
/// CLAUDE.md). Le client se contente d'insérer ou de supprimer la ligne.
abstract class SocialRepository {
  /// Vrai si l'utilisateur courant a liké ce clip.
  Future<bool> isLiked(String videoId);

  /// Ajoute un like. Idempotent : reliker ne double pas le compteur, la clé
  /// primaire `(video_id, user_id)` l'interdit.
  Future<void> like(String videoId);

  Future<void> unlike(String videoId);

  /// Fil de commentaires d'un clip, plus récents d'abord.
  Future<List<Comment>> fetchComments(
    String videoId, {
    int limit = 20,
    int offset = 0,
  });

  Future<Comment> addComment({required String videoId, required String body});

  /// Supprime un commentaire. Le serveur ne l'accepte que de son auteur (ou
  /// d'un admin) : l'artiste du clip n'a aucun droit dessus.
  Future<void> deleteComment(String commentId);

  /// Vrai si l'utilisateur courant est abonné à cet artiste.
  Future<bool> isSubscribed(String artistId);

  Future<void> subscribe(String artistId);

  Future<void> unsubscribe(String artistId);

  /// Artistes suivis par l'utilisateur courant.
  Future<List<ArtistSummary>> fetchSubscriptions();

  /// Signale un clip ou un commentaire (exactement l'un des deux).
  Future<void> report({
    String? videoId,
    String? commentId,
    required ReportReason reason,
    String? details,
  });
}

/// Erreur d'interaction sociale, porteuse d'un message affichable tel quel.
class SocialException implements Exception {
  const SocialException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Implémentation Supabase de [SocialRepository].
class SupabaseSocialRepository implements SocialRepository {
  SupabaseSocialRepository(this._client);

  final SupabaseClient _client;

  static const String _likesTable = 'likes';
  static const String _commentsTable = 'comments';
  static const String _subscriptionsTable = 'subscriptions';
  static const String _reportsTable = 'reports';

  static const String _commentWithAuthor = '''
    *,
    author:profiles!comments_author_id_fkey (
      id, username, display_name, avatar_url, role, subscriber_count
    )
  ''';

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const SocialException('Connecte-toi pour faire ça.');
    }
    return id;
  }

  @override
  Future<bool> isLiked(String videoId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    final row = await _client
        .from(_likesTable)
        .select('video_id')
        .eq('video_id', videoId)
        .eq('user_id', userId)
        .maybeSingle();
    return row != null;
  }

  @override
  Future<void> like(String videoId) async {
    // `upsert` plutôt que `insert` : un double appui ne doit pas remonter une
    // erreur de clé dupliquée à l'utilisateur.
    await _client.from(_likesTable).upsert({
      'video_id': videoId,
      'user_id': _userId,
    }, onConflict: 'video_id,user_id');
  }

  @override
  Future<void> unlike(String videoId) async {
    await _client
        .from(_likesTable)
        .delete()
        .eq('video_id', videoId)
        .eq('user_id', _userId);
  }

  @override
  Future<List<Comment>> fetchComments(
    String videoId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final rows = await _client
        .from(_commentsTable)
        .select(_commentWithAuthor)
        .eq('video_id', videoId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return rows.map<Comment>(Comment.fromJson).toList();
  }

  @override
  Future<Comment> addComment({
    required String videoId,
    required String body,
  }) async {
    try {
      final row = await _client
          .from(_commentsTable)
          .insert({
            'video_id': videoId,
            'author_id': _userId,
            'body': body.trim(),
          })
          .select(_commentWithAuthor)
          .single();
      return Comment.fromJson(row);
    } on PostgrestException catch (e) {
      throw SocialException(_commentError(e));
    }
  }

  static String _commentError(PostgrestException e) {
    final raw = '${e.message} ${e.details}'.toLowerCase();
    if (raw.contains('30 commentaires') || raw.contains('rate')) {
      return 'Tu as atteint la limite de 30 commentaires par heure. '
          'Réessaie plus tard.';
    }
    if (raw.contains('row-level security') || e.code == '42501') {
      return 'Tu ne peux pas commenter ce clip.';
    }
    return 'L\'envoi du commentaire a échoué. Réessaie.';
  }

  @override
  Future<void> deleteComment(String commentId) async {
    await _client.from(_commentsTable).delete().eq('id', commentId);
  }

  @override
  Future<bool> isSubscribed(String artistId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    final row = await _client
        .from(_subscriptionsTable)
        .select('artist_id')
        .eq('artist_id', artistId)
        .eq('subscriber_id', userId)
        .maybeSingle();
    return row != null;
  }

  @override
  Future<void> subscribe(String artistId) async {
    await _client.from(_subscriptionsTable).upsert({
      'artist_id': artistId,
      'subscriber_id': _userId,
    }, onConflict: 'artist_id,subscriber_id');
  }

  @override
  Future<void> unsubscribe(String artistId) async {
    await _client
        .from(_subscriptionsTable)
        .delete()
        .eq('artist_id', artistId)
        .eq('subscriber_id', _userId);
  }

  @override
  Future<List<ArtistSummary>> fetchSubscriptions() async {
    final rows = await _client
        .from(_subscriptionsTable)
        .select('''
          created_at,
          artist:profiles!subscriptions_artist_id_fkey (
            id, username, display_name, avatar_url, role, subscriber_count
          )
        ''')
        .eq('subscriber_id', _userId)
        .order('created_at', ascending: false);

    return rows
        .map((row) => row['artist'])
        .whereType<Map<String, dynamic>>()
        .map(ArtistSummary.fromJson)
        .toList();
  }

  @override
  Future<void> report({
    String? videoId,
    String? commentId,
    required ReportReason reason,
    String? details,
  }) async {
    assert(
      (videoId == null) != (commentId == null),
      'Un signalement vise un clip OU un commentaire, jamais les deux.',
    );
    final trimmed = details?.trim();
    try {
      await _client.from(_reportsTable).insert({
        'reporter_id': _userId,
        'video_id': ?videoId,
        'comment_id': ?commentId,
        'reason': reason.value,
        if (trimmed != null && trimmed.isNotEmpty) 'details': trimmed,
      });
    } on PostgrestException catch (e) {
      throw SocialException(_reportError(e));
    }
  }

  static String _reportError(PostgrestException e) {
    final raw = '${e.message} ${e.details}'.toLowerCase();
    if (raw.contains('duplicate') || e.code == '23505') {
      return 'Tu as déjà signalé ce contenu.';
    }
    if (raw.contains('20 signalements') || raw.contains('rate')) {
      return 'Tu as atteint la limite de 20 signalements par jour.';
    }
    return 'L\'envoi du signalement a échoué. Réessaie.';
  }
}
