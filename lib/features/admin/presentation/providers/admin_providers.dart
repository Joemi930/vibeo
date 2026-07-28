import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/utils/dev_log.dart';
import '../../data/admin_repository.dart';
import '../../domain/admin_application.dart';
import '../../domain/admin_report.dart';
import '../../domain/admin_stats.dart';
import '../../domain/admin_user.dart';
import '../../domain/admin_user_detail.dart';
import '../../domain/admin_video_queue.dart';
import '../../domain/moderation_log.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return SupabaseAdminRepository(ref.watch(supabaseClientProvider));
});

final adminStatsProvider = FutureProvider<AdminStats>((ref) {
  return ref.watch(adminRepositoryProvider).fetchStats();
});

final adminApplicationsProvider = FutureProvider<List<AdminApplication>>((ref) {
  return ref.watch(adminRepositoryProvider).fetchApplications();
});

final adminVideoQueueProvider = FutureProvider<List<AdminVideoQueueItem>>((
  ref,
) {
  return ref.watch(adminRepositoryProvider).fetchVideoQueue();
});

final adminReportsProvider = FutureProvider<List<AdminReport>>((ref) {
  return ref.watch(adminRepositoryProvider).fetchReports();
});

/// Journal, filtrable par type de cible (`null` = tout).
final adminLogsProvider =
    FutureProvider.family<List<ModerationLog>, ModerationTargetType?>((
      ref,
      filter,
    ) {
      return ref.watch(adminRepositoryProvider).fetchLogs(filter: filter);
    });

final adminUsersProvider = FutureProvider<List<AdminUser>>((ref) {
  return ref.watch(adminRepositoryProvider).fetchUsers();
});

/// Requête de recherche dans la liste des utilisateurs (filtrée côté client).
class AdminUserSearchQuery extends Notifier<String> {
  @override
  String build() => '';
  void update(String q) => state = q;
}

final adminUserSearchQueryProvider =
    NotifierProvider<AdminUserSearchQuery, String>(AdminUserSearchQuery.new);

/// Rôle sélectionné pour le filtre des utilisateurs (`null` = tous).
class AdminUserRoleFilter extends Notifier<String?> {
  @override
  String? build() => null;
  void update(String? role) => state = role;
}

final adminUserRoleFilterProvider =
    NotifierProvider<AdminUserRoleFilter, String?>(AdminUserRoleFilter.new);

/// Détail complet d'un utilisateur (profil, auth, vidéos, commentaires…).
final adminUserDetailProvider = FutureProvider.family<AdminUserDetail, String>((
  ref,
  userId,
) {
  return ref.watch(adminRepositoryProvider).fetchUserDetail(userId);
});

/// Onglet courant du dashboard, dérivé de `?tab=` par [AdminShell] et relu
/// par les widgets qui doivent, par exemple, fermer le panneau d'examen en
/// changeant d'onglet.
enum AdminTab {
  applications('applications'),
  moderation('moderation'),
  reports('reports'),
  users('users'),
  stats('stats'),
  logs('logs');

  const AdminTab(this.value);
  final String value;

  static AdminTab fromString(String? raw) {
    for (final tab in AdminTab.values) {
      if (tab.value == raw) return tab;
    }
    return AdminTab.applications;
  }
}

/// Candidature actuellement ouverte dans le panneau d'examen (`null` =
/// fermé).
class SelectedApplicationController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? applicationId) => state = applicationId;
  void close() => state = null;
}

final selectedApplicationProvider =
    NotifierProvider<SelectedApplicationController, String?>(
      SelectedApplicationController.new,
    );

/// Exécute les actions d'administration (décision, modération, résolution),
/// avec un simple indicateur « une opération est en cours ».
class AdminActionController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<String?> decideApplication({
    required String applicationId,
    required bool approve,
    required String reason,
  }) => _run(() async {
    await ref
        .read(adminRepositoryProvider)
        .decideApplication(
          applicationId: applicationId,
          approve: approve,
          reason: reason,
        );
    ref.invalidate(adminApplicationsProvider);
    ref.invalidate(adminStatsProvider);
    ref.read(selectedApplicationProvider.notifier).close();
  });

  Future<String?> moderateVideo({
    required String videoId,
    required String decision,
    String? reason,
  }) => _run(() async {
    await ref
        .read(adminRepositoryProvider)
        .moderateVideo(videoId: videoId, decision: decision, reason: reason);
    ref.invalidate(adminVideoQueueProvider);
    ref.invalidate(adminStatsProvider);
  });

  Future<String?> resolveReport({
    required String reportId,
    required String resolution,
    String? reason,
  }) => _run(() async {
    await ref
        .read(adminRepositoryProvider)
        .resolveReport(
          reportId: reportId,
          resolution: resolution,
          reason: reason,
        );
    ref.invalidate(adminReportsProvider);
    ref.invalidate(adminStatsProvider);
  });

  Future<String?> changeUserRole({
    required String userId,
    required String role,
  }) => _run(() async {
    await ref
        .read(adminRepositoryProvider)
        .changeUserRole(userId: userId, role: role);
    ref.invalidate(adminUsersProvider);
    ref.invalidate(adminStatsProvider);
  });

  Future<String?> deleteUser({required String userId, String? reason}) =>
      _run(() async {
        await ref
            .read(adminRepositoryProvider)
            .deleteUser(userId: userId, reason: reason);
        ref.invalidate(adminUsersProvider);
        ref.invalidate(adminStatsProvider);
      });

  Future<String?> createUser({
    required String email,
    required String password,
    required String username,
    required String role,
  }) => _run(() async {
    await ref
        .read(adminRepositoryProvider)
        .createUser(
          email: email,
          password: password,
          username: username,
          role: role,
        );
    ref.invalidate(adminUsersProvider);
    ref.invalidate(adminStatsProvider);
  });

  Future<String?> banUser(String userId) => _run(() async {
    await ref.read(adminRepositoryProvider).banUser(userId);
    ref.invalidate(adminUserDetailProvider(userId));
  });

  Future<String?> unbanUser(String userId) => _run(() async {
    await ref.read(adminRepositoryProvider).unbanUser(userId);
    ref.invalidate(adminUserDetailProvider(userId));
  });

  Future<String?> _run(Future<void> Function() action) async {
    if (state) return null;
    state = true;
    try {
      await action();
      return null;
    } on AdminActionException catch (e) {
      return e.message;
    } catch (error) {
      logError('action admin impossible', error);
      return 'L\'action a échoué. Réessaie.';
    } finally {
      state = false;
    }
  }
}

final adminActionControllerProvider =
    NotifierProvider<AdminActionController, bool>(AdminActionController.new);
