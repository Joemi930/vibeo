import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../auth/domain/user_role.dart';
import '../../domain/admin_user.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_data_table.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/create_user_dialog.dart';
import 'user_detail_screen.dart';

/// Onglet « Utilisateurs » du dashboard admin.
///
/// Liste les utilisateurs avec recherche, filtre par rôle, et bouton de
/// création. Un clic sur une ligne ouvre la fiche détaillée de l'utilisateur.
class UsersTab extends ConsumerStatefulWidget {
  const UsersTab({super.key});

  @override
  ConsumerState<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<UsersTab> {
  /// Utilisateur actuellement affiché en détail (`null` = vue liste).
  String? _selectedUserId;

  @override
  Widget build(BuildContext context) {
    // Vue détail
    if (_selectedUserId != null) {
      return UserDetailScreen(
        userId: _selectedUserId!,
        onBack: () => setState(() => _selectedUserId = null),
        onUserChanged: () {
          ref.invalidate(adminUsersProvider);
          ref.invalidate(adminUserDetailProvider(_selectedUserId!));
        },
      );
    }

    // Vue liste
    final usersAsync = ref.watch(adminUsersProvider);

    return usersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ErrorState(
        message: 'Impossible de charger la liste des utilisateurs.',
        onRetry: () => ref.invalidate(adminUsersProvider),
      ),
      data: (users) {
        return Stack(
          children: [
            if (users.isEmpty)
              const Center(
                child: EmptyState(
                  icon: Icons.people_rounded,
                  title: 'Aucun utilisateur',
                  message: 'Les inscriptions apparaîtront ici.',
                ),
              )
            else
              _UsersList(
                users: users,
                onUserTap: (user) => setState(() => _selectedUserId = user.id),
              ),
            // FAB de création (toujours visible, même sur liste vide)
            Positioned(
              bottom: 20,
              right: 20,
              child: FloatingActionButton.extended(
                onPressed: _createUser,
                icon: const Icon(Icons.person_add_rounded),
                label: const Text('Créer un utilisateur'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createUser() async {
    final result = await CreateUserDialog.show(context);
    if (result == null || !mounted) return;

    final error = await ref
        .read(adminActionControllerProvider.notifier)
        .createUser(
          email: result.email,
          password: result.password,
          username: result.username,
          role: result.role,
        );
    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    } else {
      ref.invalidate(adminUsersProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Compte créé : ${result.username} (${_roleLabel(result.role)}).',
          ),
        ),
      );
    }
  }
}

/// Liste des utilisateurs avec barre de recherche et filtres.
class _UsersList extends ConsumerWidget {
  const _UsersList({required this.users, required this.onUserTap});

  final List<AdminUser> users;
  final void Function(AdminUser) onUserTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchQuery = ref.watch(adminUserSearchQueryProvider).toLowerCase();
    final roleFilter = ref.watch(adminUserRoleFilterProvider);

    // Filtrage côté client
    var filtered = users;
    if (roleFilter != null) {
      filtered = filtered.where((u) => u.role.value == roleFilter).toList();
    }
    if (searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (u) =>
                u.username.toLowerCase().contains(searchQuery) ||
                (u.displayName?.toLowerCase().contains(searchQuery) ?? false),
          )
          .toList();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barre de recherche + compteur
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) =>
                      ref.read(adminUserSearchQueryProvider.notifier).update(v),
                  decoration: InputDecoration(
                    hintText: 'Rechercher un utilisateur…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () => ref
                                .read(adminUserSearchQueryProvider.notifier)
                                .update(''),
                          )
                        : null,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${filtered.length} / ${users.length}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontFamily: 'Space Mono',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Filtres par rôle
          Wrap(
            spacing: 6,
            children: [
              _RoleFilterChip(
                label: 'Tous',
                isSelected: roleFilter == null,
                onTap: () =>
                    ref.read(adminUserRoleFilterProvider.notifier).update(null),
              ),
              _RoleFilterChip(
                label: 'Auditeurs',
                isSelected: roleFilter == 'listener',
                role: UserRole.listener,
                onTap: () => ref
                    .read(adminUserRoleFilterProvider.notifier)
                    .update('listener'),
              ),
              _RoleFilterChip(
                label: 'Artistes',
                isSelected: roleFilter == 'artist',
                role: UserRole.artist,
                onTap: () => ref
                    .read(adminUserRoleFilterProvider.notifier)
                    .update('artist'),
              ),
              _RoleFilterChip(
                label: 'Admins',
                isSelected: roleFilter == 'admin',
                role: UserRole.admin,
                onTap: () => ref
                    .read(adminUserRoleFilterProvider.notifier)
                    .update('admin'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Tableau
          Expanded(
            child: filtered.isEmpty
                ? const EmptyState(
                    icon: Icons.filter_list_off_rounded,
                    title: 'Aucun résultat',
                    message: 'Essaie un autre filtre ou un autre terme.',
                  )
                : _UsersTable(users: filtered, onUserTap: onUserTap),
          ),
        ],
      ),
    );
  }
}

/// Filtre par rôle sous forme de chip.
class _RoleFilterChip extends StatelessWidget {
  const _RoleFilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.role,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final UserRole? role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color? bgColor;
    Color? fgColor;
    if (isSelected && role != null) {
      final (fg, bg, _) = _roleBadgeColors(role!, theme);
      bgColor = bg;
      fgColor = fg;
    }

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      backgroundColor: bgColor,
      selectedColor: bgColor,
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        color:
            fgColor ??
            (isSelected
                ? theme.colorScheme.onSecondaryContainer
                : theme.colorScheme.onSurfaceVariant),
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: isSelected ? BorderSide.none : null,
    );
  }
}

class _UsersTable extends ConsumerWidget {
  const _UsersTable({required this.users, required this.onUserTap});

  final List<AdminUser> users;
  final void Function(AdminUser) onUserTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final columns = const [
      ColumnDef(label: 'Utilisateur', flex: 2.2),
      ColumnDef(label: 'Rôle', flex: 1),
      ColumnDef(label: 'Inscrit le', flex: 1),
      ColumnDef(label: 'Actions', flex: 1, alignment: Alignment.centerRight),
    ];

    final rows = <List<Widget>>[];
    for (var i = 0; i < users.length; i++) {
      final user = users[i];
      rows.add([
        // Nom + username
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                user.resolvedName[0].toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user.resolvedName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '@${user.username}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),

        // Rôle
        _RoleBadge(role: user.role),

        // Date d'inscription
        Text(
          '${user.createdAt.day.toString().padLeft(2, '0')}/'
          '${user.createdAt.month.toString().padLeft(2, '0')}/'
          '${user.createdAt.year}',
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
                IconButton(
                  tooltip: 'Voir le détail',
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  onPressed: () => onUserTap(user),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Actions',
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  onSelected: (action) {
                    switch (action) {
                      case 'role':
                        _showRolePopup(rowContext, ref, user);
                      case 'delete':
                        _deleteUser(rowContext, ref, user);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'role',
                      child: ListTile(
                        leading: Icon(Icons.manage_accounts_rounded),
                        title: Text('Changer le rôle'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red,
                        ),
                        title: Text(
                          'Supprimer',
                          style: TextStyle(color: Colors.red),
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
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
      onRowTap: (i) => onUserTap(users[i]),
    );
  }

  void _showRolePopup(BuildContext context, WidgetRef ref, AdminUser user) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Changer le rôle de @${user.username}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Rôle actuel : ${_roleLabel(user.role.value)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (user.role != UserRole.listener)
                  ListTile(
                    leading: const Icon(Icons.headphones_rounded),
                    title: const Text('Auditeur'),
                    subtitle: const Text('Retire tous les privilèges.'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _changeRole(context, ref, user, 'listener');
                    },
                  ),
                if (user.role != UserRole.artist)
                  ListTile(
                    leading: const Icon(Icons.mic_rounded),
                    title: const Text('Artiste'),
                    subtitle: const Text('Peut publier des clips.'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _changeRole(context, ref, user, 'artist');
                    },
                  ),
                if (user.role != UserRole.admin)
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings_rounded),
                    title: const Text('Administrateur'),
                    subtitle: const Text('Accès complet au dashboard.'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _changeRole(context, ref, user, 'admin');
                    },
                  ),
              ],
            ),
          ),
        );
      },
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
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (Color fg, Color bg, String label) = _roleBadgeColors(role, theme);

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

/// Couleurs et libellé d'un badge de rôle. Extraite pour être réutilisée
/// dans [_RoleFilterChip] et [_RoleBadge].
(Color fg, Color bg, String label) _roleBadgeColors(
  UserRole role,
  ThemeData theme,
) {
  return switch (role) {
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
}

String _roleLabel(String role) {
  return switch (role) {
    'listener' => 'Auditeur',
    'artist' => 'Artiste',
    'admin' => 'Administrateur',
    _ => role,
  };
}
