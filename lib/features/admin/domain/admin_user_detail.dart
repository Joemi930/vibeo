import '../../auth/domain/user_role.dart';

/// Données du compte Auth Supabase (email, bannissement, dates).
class AdminUserAuth {
  const AdminUserAuth({
    this.email,
    this.lastSignInAt,
    this.createdAt,
    this.isBanned = false,
    this.bannedUntil,
  });

  final String? email;
  final DateTime? lastSignInAt;
  final DateTime? createdAt;
  final bool isBanned;
  final DateTime? bannedUntil;

  factory AdminUserAuth.fromJson(Map<String, dynamic> json) {
    return AdminUserAuth(
      email: json['email'] as String?,
      lastSignInAt: json['lastSignInAt'] != null
          ? DateTime.parse(json['lastSignInAt'] as String)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      isBanned: json['isBanned'] as bool? ?? false,
      bannedUntil: json['bannedUntil'] != null
          ? DateTime.parse(json['bannedUntil'] as String)
          : null,
    );
  }
}

/// Commentaire d'un utilisateur dans la fiche de détail admin.
class AdminUserComment {
  const AdminUserComment({
    required this.id,
    required this.videoId,
    required this.body,
    required this.createdAt,
    this.deletedAt,
  });

  final String id;
  final String videoId;
  final String body;
  final DateTime createdAt;
  final DateTime? deletedAt;

  factory AdminUserComment.fromJson(Map<String, dynamic> json) {
    return AdminUserComment(
      id: json['id'] as String,
      videoId: json['video_id'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
    );
  }
}

/// Playlist dans la fiche de détail admin.
class AdminUserPlaylist {
  const AdminUserPlaylist({
    required this.id,
    required this.title,
    this.description,
    required this.isPublic,
    required this.itemCount,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String? description;
  final bool isPublic;
  final int itemCount;
  final DateTime createdAt;

  factory AdminUserPlaylist.fromJson(Map<String, dynamic> json) {
    return AdminUserPlaylist(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      isPublic: json['is_public'] as bool? ?? false,
      itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Abonnement dans la fiche de détail admin.
class AdminUserSubscription {
  const AdminUserSubscription({
    required this.artistId,
    this.artistUsername,
    this.artistDisplayName,
    required this.createdAt,
  });

  final String artistId;
  final String? artistUsername;
  final String? artistDisplayName;
  final DateTime createdAt;

  factory AdminUserSubscription.fromJson(Map<String, dynamic> json) {
    return AdminUserSubscription(
      artistId: json['artist_id'] as String,
      artistUsername: json['artistUsername'] as String?,
      artistDisplayName: json['artistDisplayName'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Abonné dans la fiche de détail admin.
class AdminUserSubscriber {
  const AdminUserSubscriber({
    required this.subscriberId,
    this.subscriberUsername,
    this.subscriberDisplayName,
    required this.createdAt,
  });

  final String subscriberId;
  final String? subscriberUsername;
  final String? subscriberDisplayName;
  final DateTime createdAt;

  factory AdminUserSubscriber.fromJson(Map<String, dynamic> json) {
    return AdminUserSubscriber(
      subscriberId: json['subscriber_id'] as String,
      subscriberUsername: json['subscriberUsername'] as String?,
      subscriberDisplayName: json['subscriberDisplayName'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Signalement dans la fiche de détail admin.
class AdminUserReport {
  const AdminUserReport({
    required this.id,
    required this.targetKind,
    this.videoId,
    this.commentId,
    required this.reason,
    this.details,
    required this.status,
    required this.createdAt,
    this.reviewedAt,
  });

  final String id;
  final String targetKind;
  final String? videoId;
  final String? commentId;
  final String reason;
  final String? details;
  final String status;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  factory AdminUserReport.fromJson(Map<String, dynamic> json) {
    return AdminUserReport(
      id: json['id'] as String,
      targetKind: json['target_kind'] as String,
      videoId: json['video_id'] as String?,
      commentId: json['comment_id'] as String?,
      reason: json['reason'] as String,
      details: json['details'] as String?,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
    );
  }
}

/// Journal de modération dans la fiche de détail admin.
class AdminUserModLog {
  const AdminUserModLog({
    required this.id,
    required this.actor,
    required this.targetType,
    required this.action,
    this.reason,
    required this.createdAt,
  });

  final String id;
  final String actor;
  final String targetType;
  final String action;
  final String? reason;
  final DateTime createdAt;

  factory AdminUserModLog.fromJson(Map<String, dynamic> json) {
    return AdminUserModLog(
      id: json['id'] as String,
      actor: json['actor'] as String,
      targetType: json['target_type'] as String,
      action: json['action'] as String,
      reason: json['reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Détail complet d'un utilisateur pour la fiche admin.
///
/// Agrège toutes les données : profil, auth, vidéos, commentaires, playlists,
/// abonnements, signalements et journal de modération. Récupéré via l'Edge
/// Function `admin-actions` (action `get_user_detail`), qui utilise le
/// `service_role` pour contourner les restrictions RLS (ex. abonnements privés).
class AdminUserDetail {
  const AdminUserDetail({
    required this.profile,
    required this.auth,
    required this.videos,
    required this.comments,
    required this.playlists,
    required this.subscriptions,
    required this.subscribers,
    required this.reportsFiled,
    required this.reportsAgainst,
    required this.moderationLogs,
  });

  final Map<String, dynamic> profile;
  final AdminUserAuth auth;
  final List<Map<String, dynamic>> videos;
  final List<AdminUserComment> comments;
  final List<AdminUserPlaylist> playlists;
  final List<AdminUserSubscription> subscriptions;
  final List<AdminUserSubscriber> subscribers;
  final List<AdminUserReport> reportsFiled;
  final List<AdminUserReport> reportsAgainst;
  final List<AdminUserModLog> moderationLogs;

  // ── Dérivés pratiques (évite de lire le JSON brut dans l'UI) ──

  String get id => profile['id'] as String;
  String get username => profile['username'] as String;
  String? get displayName => profile['display_name'] as String?;
  String? get avatarUrl => profile['avatar_url'] as String?;
  String? get bio => profile['bio'] as String?;
  UserRole get role => UserRole.fromString(profile['role'] as String?);
  DateTime get profileCreatedAt =>
      DateTime.parse(profile['created_at'] as String);

  String get resolvedName => displayName ?? username;
  bool get isArtist => role == UserRole.artist;
  int get videoCount => videos.length;
  int get commentCount => comments.length;
  int get playlistCount => playlists.length;
  int get subscriptionCount => subscriptions.length;
  int get subscriberCount => subscribers.length;

  factory AdminUserDetail.fromJson(Map<String, dynamic> json) {
    return AdminUserDetail(
      profile: (json['profile'] as Map<String, dynamic>?) ?? {},
      auth: AdminUserAuth.fromJson(
        (json['auth'] as Map<String, dynamic>?) ?? {},
      ),
      videos:
          (json['videos'] as List?)
              ?.map((v) => v as Map<String, dynamic>)
              .toList() ??
          [],
      comments:
          (json['comments'] as List?)
              ?.map((c) => AdminUserComment.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      playlists:
          (json['playlists'] as List?)
              ?.map(
                (p) => AdminUserPlaylist.fromJson(p as Map<String, dynamic>),
              )
              .toList() ??
          [],
      subscriptions:
          (json['subscriptions'] as List?)
              ?.map(
                (s) =>
                    AdminUserSubscription.fromJson(s as Map<String, dynamic>),
              )
              .toList() ??
          [],
      subscribers:
          (json['subscribers'] as List?)
              ?.map(
                (s) => AdminUserSubscriber.fromJson(s as Map<String, dynamic>),
              )
              .toList() ??
          [],
      reportsFiled:
          (json['reportsFiled'] as List?)
              ?.map((r) => AdminUserReport.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      reportsAgainst:
          (json['reportsAgainst'] as List?)
              ?.map((r) => AdminUserReport.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      moderationLogs:
          (json['moderationLogs'] as List?)
              ?.map((l) => AdminUserModLog.fromJson(l as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
