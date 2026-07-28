import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/admin_application.dart';
import '../domain/admin_report.dart';
import '../domain/admin_stats.dart';
import '../domain/admin_user.dart';
import '../domain/admin_user_detail.dart';
import '../domain/admin_video_queue.dart';
import '../domain/moderation_log.dart';

/// Erreur d'action admin, porteuse d'un message déjà traduisible tel quel.
///
/// L'Edge Function `admin-actions` répond 404 (et non 403) à un non-admin :
/// ce n'est jamais présenté comme un refus d'accès, mais comme un échec
/// générique — ne rien révéler de la garde côté serveur.
class AdminActionException implements Exception {
  const AdminActionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Contrat d'accès aux données et actions d'administration.
///
/// Toute lecture passe par les vues `admin_*` (RLS `is_admin()` déjà
/// intégrée) ; toute écriture passe par l'Edge Function `admin-actions` — un
/// admin connecté reste `authenticated`, pas `service_role`, et ne peut donc
/// pas modifier directement `videos`/`profiles`/`artist_applications`.
abstract class AdminRepository {
  Future<AdminStats> fetchStats();

  Future<List<AdminApplication>> fetchApplications();

  Future<List<AdminVideoQueueItem>> fetchVideoQueue();

  Future<List<AdminReport>> fetchReports();

  Future<List<ModerationLog>> fetchLogs({ModerationTargetType? filter});

  /// Demande une URL signée (5 min) vers le document d'identité d'une
  /// candidature. Chaque appel est journalisé côté serveur.
  Future<({String url, int expiresIn})> documentUrl(String applicationId);

  Future<void> decideApplication({
    required String applicationId,
    required bool approve,
    required String reason,
  });

  Future<void> moderateVideo({
    required String videoId,
    required String decision,
    String? reason,
  });

  Future<void> resolveReport({
    required String reportId,
    required String resolution,
    String? reason,
  });

  /// Liste des utilisateurs (vue `admin_users`, admin uniquement).
  Future<List<AdminUser>> fetchUsers();

  /// Change le rôle d'un utilisateur (listener, artist, admin).
  Future<void> changeUserRole({required String userId, required String role});

  /// Supprime définitivement un compte utilisateur.
  Future<void> deleteUser({required String userId, String? reason});

  /// Récupère le détail complet d'un utilisateur (profil, auth, vidéos,
  /// commentaires, playlists, abonnements, signalements, journal).
  Future<AdminUserDetail> fetchUserDetail(String userId);

  /// Crée un utilisateur avec email, mot de passe, username et rôle.
  /// Retourne l'ID du nouvel utilisateur.
  Future<String> createUser({
    required String email,
    required String password,
    required String username,
    required String role,
  });

  /// Bannit un utilisateur (empêche toute connexion).
  Future<void> banUser(String userId);

  /// Lève le bannissement d'un utilisateur.
  Future<void> unbanUser(String userId);
}

/// Implémentation Supabase de [AdminRepository].
class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository(this._client);

  final SupabaseClient _client;

  static const String _functionName = 'admin-actions';

  @override
  Future<AdminStats> fetchStats() async {
    final row = await _client.from('admin_stats').select().maybeSingle();
    if (row == null) {
      return const AdminStats(
        userCount: 0,
        artistCount: 0,
        publishedVideoCount: 0,
        moderationQueueCount: 0,
        applicationQueueCount: 0,
        openReportCount: 0,
        totalViewCount: 0,
        storageBytesUsed: 0,
        storageBytesLimit: 1073741824,
      );
    }
    return AdminStats.fromJson(row);
  }

  @override
  Future<List<AdminApplication>> fetchApplications() async {
    final rows = await _client
        .from('admin_artist_applications')
        .select()
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => AdminApplication.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<AdminVideoQueueItem>> fetchVideoQueue() async {
    final rows = await _client
        .from('admin_video_queue')
        .select()
        .order('created_at');
    return (rows as List)
        .map((r) => AdminVideoQueueItem.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<AdminReport>> fetchReports() async {
    final rows =
        await _client
                .from('reports')
                .select()
                .order('priority', ascending: false)
                .order('created_at')
            as List;
    final reports = rows
        .map((r) => AdminReport.fromJson(r as Map<String, dynamic>))
        .toList();
    if (reports.isEmpty) return reports;

    // Contexte (noms, titres) résolu par des requêtes séparées plutôt que par
    // un embed PostgREST : plusieurs clés étrangères de `reports` pointent
    // vers `profiles` (reporter_id, target_author_id, reviewed_by), ce qui
    // rend l'embed ambigu sans connaître le nom exact de la contrainte.
    final profileIds = <String>{
      for (final r in reports) r.reporterId,
      for (final r in reports)
        if (r.targetAuthorId != null) r.targetAuthorId!,
    };
    final videoIds = [
      for (final r in reports)
        if (r.videoId != null) r.videoId!,
    ];
    final commentIds = [
      for (final r in reports)
        if (r.commentId != null) r.commentId!,
    ];

    final profiles = profileIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _client
                  .from('profiles')
                  .select('id, username')
                  .inFilter('id', profileIds.toList())
              as List;
    final usernames = {
      for (final p in profiles) p['id'] as String: p['username'] as String?,
    };

    final videos = videoIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _client
                  .from('videos')
                  .select('id, title')
                  .inFilter('id', videoIds)
              as List;
    final videoTitles = {
      for (final v in videos) v['id'] as String: v['title'] as String?,
    };

    final comments = commentIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _client
                  .from('comments')
                  .select('id, content')
                  .inFilter('id', commentIds)
              as List;
    final commentContents = {
      for (final c in comments) c['id'] as String: c['content'] as String?,
    };

    return reports
        .map(
          (r) => r.copyWithContext(
            reporterUsername: usernames[r.reporterId],
            targetAuthorUsername: usernames[r.targetAuthorId],
            videoTitle: videoTitles[r.videoId],
            commentContent: commentContents[r.commentId],
          ),
        )
        .toList();
  }

  @override
  Future<List<ModerationLog>> fetchLogs({ModerationTargetType? filter}) async {
    var query = _client.from('moderation_logs').select();
    if (filter != null) {
      query = query.eq('target_type', filter.value);
    }
    final rows = await query.order('created_at', ascending: false).limit(200);
    return (rows as List)
        .map((r) => ModerationLog.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<({String url, int expiresIn})> documentUrl(
    String applicationId,
  ) async {
    final response = await _invoke({
      'action': 'document_url',
      'applicationId': applicationId,
    });
    return (
      url: response['url'] as String,
      expiresIn: (response['expiresIn'] as num).toInt(),
    );
  }

  @override
  Future<void> decideApplication({
    required String applicationId,
    required bool approve,
    required String reason,
  }) async {
    await _invoke({
      'action': 'decide_application',
      'applicationId': applicationId,
      'decision': approve ? 'approved' : 'rejected',
      'reason': reason,
    });
  }

  @override
  Future<void> moderateVideo({
    required String videoId,
    required String decision,
    String? reason,
  }) async {
    await _invoke({
      'action': 'moderate_video',
      'videoId': videoId,
      'decision': decision,
      // ignore: use_null_aware_elements
      if (reason != null) 'reason': reason,
    });
  }

  @override
  Future<void> resolveReport({
    required String reportId,
    required String resolution,
    String? reason,
  }) async {
    await _invoke({
      'action': 'resolve_report',
      'reportId': reportId,
      'resolution': resolution,
      // ignore: use_null_aware_elements
      if (reason != null) 'reason': reason,
    });
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions.invoke(
        _functionName,
        body: body,
      );
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return data.cast<String, dynamic>();
      return const {};
    } on FunctionException catch (e) {
      throw AdminActionException(_messageFor(e, body['action'] as String?));
    }
  }

  // ── Méthodes pour la gestion avancée des utilisateurs ──────────────────

  @override
  Future<AdminUserDetail> fetchUserDetail(String userId) async {
    final data = await _invoke({'action': 'get_user_detail', 'userId': userId});
    return AdminUserDetail.fromJson(data);
  }

  @override
  Future<String> createUser({
    required String email,
    required String password,
    required String username,
    required String role,
  }) async {
    final data = await _invoke({
      'action': 'create_user',
      'email': email,
      'password': password,
      'username': username,
      'role': role,
    });
    final userId = data['userId'] as String?;
    if (userId == null) {
      throw const AdminActionException('La création du compte a échoué.');
    }
    return userId;
  }

  @override
  Future<void> banUser(String userId) async {
    await _invoke({'action': 'ban_user', 'userId': userId});
  }

  @override
  Future<void> unbanUser(String userId) async {
    await _invoke({'action': 'unban_user', 'userId': userId});
  }

  // ── Suite des méthodes existantes ──────────────────────────────────────

  @override
  Future<List<AdminUser>> fetchUsers() async {
    final rows = await _client
        .from('admin_users')
        .select()
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => AdminUser.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> changeUserRole({
    required String userId,
    required String role,
  }) async {
    await _invoke({
      'action': 'change_user_role',
      'userId': userId,
      'role': role,
    });
  }

  @override
  Future<void> deleteUser({required String userId, String? reason}) async {
    await _invoke({
      'action': 'delete_user',
      'userId': userId,
      // ignore: use_null_aware_elements
      if (reason != null) 'reason': reason,
    });
  }

  String _messageFor(FunctionException e, [String? action]) {
    final detail = e.details;
    String? serverError;
    if (detail is Map) {
      serverError = (detail['error'] ?? detail['message']) as String?;
    } else if (detail is String && detail.isNotEmpty) {
      serverError = detail;
    }

    final suffix = serverError != null ? ' ($serverError)' : '';
    final actionInfo = action != null ? ' [$action]' : '';

    switch (e.status) {
      case 404:
      case 401:
        return 'L\'action n\'a pas pu être effectuée. Réessaie.$suffix$actionInfo';
      case 409:
        return serverError ?? 'Cet élément a déjà été traité.$actionInfo';
      case 400:
        return serverError ?? 'Requête invalide.$actionInfo';
      default:
        return 'L\'action a échoué (${e.status}). Réessaie.$suffix$actionInfo';
    }
  }
}
