import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../auth/domain/user_role.dart';
import '../../domain/admin_user.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_data_table.dart';
import '../widgets/confirm_action_dialog.dart';

/// Onglet « Utilisateurs » du dashboard admin.
///
/// Liste tous les utilisateurs avec leur rôle, et permet de changer le rôle
/// ou de supprimer un compte.
class UsersTab extends ConsumerWidget {
  const UsersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(adminUsersProvider);

    return usersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ErrorState(
        message: 'Impossible de charger la liste des utilisateurs.',
        onRetry: () => ref.invalidate(adminUsersProvider),
      ),
      data: (users) {
        if (users.isEmpty) {
          return const EmptyState(
            icon: Icons.people_rounded,
            title: 'Aucun utilisateur',
            message: 'Les inscriptions apparaîtront ici.',
          );
        }
        return Padding(
          padding: const EdgeInsets.all(20),
          child: _UsersTable(users: users),
        );
      },
    );
  }
}

class _UsersTable extends ConsumerWidget {
  const _UsersTable({required this.users});

  final List<AdminUser> users;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final columns = const [
      ColumnDef(label: 'Utilisateur', flex: 2),
      ColumnDef(label: 'Rôle', flex: 1),
      ColumnDef(label: 'Inscrit le', flex: 1.2),
      ColumnDef(label: 'Actions', flex: 1.4, alignment: Alignment.centerRight),
    ];

    final rows = <List<Widget>>[];
    for (final user in users) {
      rows.add([
        // Nom + username
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              user.resolvedName,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '@${user.username}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),

        // Rôle
        _RoleBadge(role: user.role),

        // Date d'inscription
        Text(
          '${user.createdAt.day}/${user.createdAt.month}/${user.createdAt.year}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),

        // Actions
        Builder(
          builder: (rowContext) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<String>(
                  tooltip: 'Changer le rôle',
                  icon: const Icon(Icons.manage_accounts_rounded, size: 20),
                  onSelected: (role) =>
                      _changeRole(rowContext, ref, user, role),
                  itemBuilder: (_) => [
                    if (user.role != UserRole.listener)
                      const PopupMenuItem(
                        value: 'listener',
                        child: Text('Auditeur'),
                      ),
                    if (user.role != UserRole.artist)
                      const PopupMenuItem(
                        value: 'artist',
                        child: Text('Artiste'),
                      ),
                    if (user.role != UserRole.admin)
                      const PopupMenuItem(
                        value: 'admin',
                        child: Text('Administrateur'),
                      ),
                  ],
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Supprimer le compte',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: theme.colorScheme.error,
                  onPressed: () => _deleteUser(rowContext, ref, user),
                ),
              ],
            );
          },
        ),
      ]);
    }

    return AdminDataTable(
      columns: columns,
      rows: rows,
      emptyMessage: 'Aucun utilisateur.',
    );
  }

  Future<void> _changeRole(
    BuildContext context,
    WidgetRef ref,
    AdminUser user,
    String newRole,
  ) async {
    final roleLabel = _roleLabel(newRole);
    final confirmed = await showConfirmActionDialog(
      context: context,
      title: 'Changer le rôle de @${user.username} ?',
      message:
          'Son rôle passera de « ${_roleLabel(user.role.value)} » '
          'à « $roleLabel ».',
      confirmLabel: 'Changer en $roleLabel',
      isDestructive: newRole == 'listener',
      requireReason: false,
    );
    if (!confirmed.confirmed || !context.mounted) return;

    final error = await ref
        .read(adminActionControllerProvider.notifier)
        .changeUserRole(userId: user.id, role: newRole);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _deleteUser(
    BuildContext context,
    WidgetRef ref,
    AdminUser user,
  ) async {
    final result = await showConfirmActionDialog(
      context: context,
      title: 'Supprimer @${user.username} ?',
      message:
          'Cette action est IRRÉVERSIBLE. Tous les clips, commentaires '
          'et playlists de cet utilisateur seront définitivement supprimés.',
      confirmLabel: 'Supprimer définitivement',
      isDestructive: true,
      requireReason: true,
      reasonLabel: 'Motif de la suppression',
    );
    if (!result.confirmed || !context.mounted) return;

    final error = await ref
        .read(adminActionControllerProvider.notifier)
        .deleteUser(userId: user.id, reason: result.reason);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  String _roleLabel(String role) {
    return switch (role) {
      'listener' => 'Auditeur',
      'artist' => 'Artiste',
      'admin' => 'Administrateur',
      _ => role,
    };
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (Color fg, Color bg, String label) = switch (role) {
      UserRole.admin => (
        const Color(0xFF7C3AED),
        const Color(0xFFEDE9FE),
        'Admin',
      ),
      UserRole.artist => (
        const Color(0xFF059669),
        const Color(0xFFD1FAE5),
        'Artiste',
      ),
      UserRole.listener => (
        theme.colorScheme.onSurfaceVariant,
        theme.colorScheme.surfaceContainerHighest,
        'Auditeur',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
