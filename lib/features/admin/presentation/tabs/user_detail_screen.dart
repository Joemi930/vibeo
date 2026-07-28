import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../auth/domain/user_role.dart';
import '../../domain/admin_user_detail.dart';
import '../providers/admin_providers.dart';
import '../widgets/confirm_action_dialog.dart';

/// Écran de détail d'un utilisateur dans le dashboard admin.
///
/// Affiche toutes les informations d'un utilisateur : profil, compte Auth,
/// vidéos (si artiste), commentaires, playlists, abonnements, signalements
/// et journal de modération. Chaque section est filtrable.
class UserDetailScreen extends ConsumerStatefulWidget {
  const UserDetailScreen({
    required this.userId,
    required this.onBack,
    required this.onUserChanged,
    super.key,
  });

  final String userId;
  final VoidCallback onBack;
  final VoidCallback onUserChanged;

  @override
  ConsumerState<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends ConsumerState<UserDetailScreen> {
  /// Section actuellement affichée dans l'onglet détail.
  String _section = 'videos';

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(adminUserDetailProvider(widget.userId));

    return detailAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ErrorState(
            message: 'Impossible de charger le détail de l\'utilisateur.',
            onRetry: () =>
                ref.invalidate(adminUserDetailProvider(widget.userId)),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Retour à la liste'),
          ),
        ],
      ),
      data: (detail) => _buildDetail(context, detail),
    );
  }

  Widget _buildDetail(BuildContext context, AdminUserDetail detail) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // En-tête avec bouton retour
          _DetailHeader(
            detail: detail,
            onBack: widget.onBack,
            onBan: () => _toggleBan(detail),
            onChangeRole: () => _showRoleChanger(detail),
            onDelete: () => _deleteUser(detail),
          ),
          const SizedBox(height: 16),

          // Corps avec sections
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Carte profil + auth (largeur fixe)
                SizedBox(
                  width: 280,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _ProfileCard(detail: detail),
                        const SizedBox(height: 12),
                        _AuthCard(detail: detail),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Sections détaillées (reste de l'espace)
                Expanded(
                  child: Column(
                    children: [
                      // Barre d'onglets des sections
                      _SectionTabs(
                        detail: detail,
                        current: _section,
                        onChanged: (s) => setState(() => _section = s),
                      ),
                      const SizedBox(height: 12),
                      // Contenu de la section
                      Expanded(child: _buildSection(detail)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(AdminUserDetail detail) {
    return switch (_section) {
      'videos' => _VideosSection(videos: detail.videos),
      'comments' => _CommentsSection(comments: detail.comments),
      'playlists' => _PlaylistsSection(playlists: detail.playlists),
      'subscriptions' => _SubsSection(
        subscriptions: detail.subscriptions,
        subscribers: detail.subscribers,
        detail: detail,
      ),
      'reports' => _ReportsSection(
        filed: detail.reportsFiled,
        against: detail.reportsAgainst,
      ),
      'logs' => _ModLogsSection(logs: detail.moderationLogs),
      _ => const SizedBox.shrink(),
    };
  }

  // ── Actions admin ──────────────────────────────────────────────────────

  Future<void> _toggleBan(AdminUserDetail detail) async {
    final isBanned = detail.auth.isBanned;
    final confirmed = await showConfirmActionDialog(
      context: context,
      title: isBanned
          ? 'Débannir @${detail.username} ?'
          : 'Bannir @${detail.username} ?',
      message: isBanned
          ? 'L\'utilisateur pourra de nouveau se connecter.'
          : 'L\'utilisateur ne pourra PLUS se connecter (même via Google). '
                'Cette action est réversible.',
      confirmLabel: isBanned ? 'Débannir' : 'Bannir définitivement',
      isDestructive: !isBanned,
      requireReason: false,
    );
    if (!confirmed.confirmed || !mounted) return;

    final error = isBanned
        ? await ref
              .read(adminActionControllerProvider.notifier)
              .unbanUser(widget.userId)
        : await ref
              .read(adminActionControllerProvider.notifier)
              .banUser(widget.userId);

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    } else {
      ref.invalidate(adminUserDetailProvider(widget.userId));
      widget.onUserChanged();
    }
  }

  Future<void> _showRoleChanger(AdminUserDetail detail) async {
    final newRole = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Changer le rôle de @${detail.username}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (detail.role != UserRole.listener)
                  ListTile(
                    leading: const Icon(Icons.headphones_rounded),
                    title: const Text('Auditeur'),
                    onTap: () => Navigator.pop(ctx, 'listener'),
                  ),
                if (detail.role != UserRole.artist)
                  ListTile(
                    leading: const Icon(Icons.mic_rounded),
                    title: const Text('Artiste'),
                    onTap: () => Navigator.pop(ctx, 'artist'),
                  ),
                if (detail.role != UserRole.admin)
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings_rounded),
                    title: const Text('Administrateur'),
                    onTap: () => Navigator.pop(ctx, 'admin'),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (newRole == null || !mounted) return;

    final error = await ref
        .read(adminActionControllerProvider.notifier)
        .changeUserRole(userId: widget.userId, role: newRole);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    } else {
      ref.invalidate(adminUserDetailProvider(widget.userId));
      widget.onUserChanged();
    }
  }

  Future<void> _deleteUser(AdminUserDetail detail) async {
    final result = await showConfirmActionDialog(
      context: context,
      title: 'Supprimer @${detail.username} ?',
      message:
          'Cette action est IRRÉVERSIBLE. Tous les clips, commentaires '
          'et playlists seront définitivement supprimés.',
      confirmLabel: 'Supprimer définitivement',
      isDestructive: true,
      requireReason: true,
      reasonLabel: 'Motif de la suppression',
    );
    if (!result.confirmed || !mounted) return;

    final error = await ref
        .read(adminActionControllerProvider.notifier)
        .deleteUser(userId: widget.userId, reason: result.reason);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    } else {
      widget.onUserChanged();
      widget.onBack();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// En-tête
// ═══════════════════════════════════════════════════════════════════════════

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.detail,
    required this.onBack,
    required this.onBan,
    required this.onChangeRole,
    required this.onDelete,
  });

  final AdminUserDetail detail;
  final VoidCallback onBack;
  final VoidCallback onBan;
  final VoidCallback onChangeRole;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Retour à la liste',
        ),
        const SizedBox(width: 8),
        CircleAvatar(
          radius: 22,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            detail.resolvedName[0].toUpperCase(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      detail.resolvedName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _RoleBadge(role: detail.role),
                  if (detail.auth.isBanned) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'BANNI',
                        style: TextStyle(
                          fontFamily: 'Space Mono',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                '@${detail.username} · ${detail.auth.email ?? 'Email masqué'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Actions
        PopupMenuButton<String>(
          tooltip: 'Actions',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (action) {
            switch (action) {
              case 'ban':
                onBan();
              case 'role':
                onChangeRole();
              case 'delete':
                onDelete();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'role',
              child: ListTile(
                leading: const Icon(Icons.manage_accounts_rounded),
                title: const Text('Changer le rôle'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'ban',
              child: ListTile(
                leading: Icon(
                  detail.auth.isBanned
                      ? Icons.lock_open_rounded
                      : Icons.block_rounded,
                ),
                title: Text(detail.auth.isBanned ? 'Débannir' : 'Bannir'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red,
                ),
                title: const Text(
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
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Cartes profil + auth
// ═══════════════════════════════════════════════════════════════════════════

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.detail});

  final AdminUserDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Profil',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            _InfoRow(label: 'ID', value: '${detail.id.substring(0, 12)}…'),
            _InfoRow(label: 'Username', value: '@${detail.username}'),
            if (detail.displayName != null)
              _InfoRow(label: 'Nom affiché', value: detail.displayName!),
            if (detail.bio != null && detail.bio!.isNotEmpty)
              _InfoRow(label: 'Bio', value: detail.bio!, maxLines: 3),
            _InfoRow(
              label: 'Inscrit le',
              value:
                  '${detail.profileCreatedAt.day}/${detail.profileCreatedAt.month}/${detail.profileCreatedAt.year}',
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({required this.detail});

  final AdminUserDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = detail.auth;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compte Auth',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            _InfoRow(label: 'Email', value: auth.email ?? 'Non disponible'),
            _InfoRow(
              label: 'Dernière connexion',
              value: auth.lastSignInAt != null
                  ? '${auth.lastSignInAt!.day}/${auth.lastSignInAt!.month}/${auth.lastSignInAt!.year} '
                        '${auth.lastSignInAt!.hour}h${auth.lastSignInAt!.minute.toString().padLeft(2, '0')}'
                  : 'Jamais',
            ),
            _InfoRow(
              label: 'Statut',
              value: auth.isBanned ? 'Banni' : 'Actif',
              valueColor: auth.isBanned
                  ? theme.colorScheme.error
                  : const Color(0xFF059669),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.maxLines = 1,
    this.valueColor,
  });

  final String label;
  final String value;
  final int maxLines;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Onglets des sections
// ═══════════════════════════════════════════════════════════════════════════

class _SectionTabs extends StatelessWidget {
  const _SectionTabs({
    required this.detail,
    required this.current,
    required this.onChanged,
  });

  final AdminUserDetail detail;
  final String current;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final tabs = [
      if (detail.isArtist || detail.videos.isNotEmpty)
        ('Vidéos', detail.videoCount, 'videos'),
      ('Commentaires', detail.commentCount, 'comments'),
      ('Playlists', detail.playlistCount, 'playlists'),
      (
        'Abonnements',
        detail.subscriptionCount + detail.subscriberCount,
        'subscriptions',
      ),
      (
        'Signalements',
        detail.reportsFiled.length + detail.reportsAgainst.length,
        'reports',
      ),
      ('Journal', detail.moderationLogs.length, 'logs'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (label, count, key) in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                label: Text('$label ($count)'),
                selected: current == key,
                onSelected: (_) => onChanged(key),
                labelStyle: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: current == key
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Section Vidéos
// ═══════════════════════════════════════════════════════════════════════════

class _VideosSection extends ConsumerStatefulWidget {
  const _VideosSection({required this.videos});

  final List<Map<String, dynamic>> videos;

  @override
  ConsumerState<_VideosSection> createState() => _VideosSectionState();
}

class _VideosSectionState extends ConsumerState<_VideosSection> {
  String _statusFilter = 'all';
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    var filtered = widget.videos;
    if (_statusFilter != 'all') {
      filtered = filtered.where((v) => v['status'] == _statusFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered
          .where(
            (v) => (v['title'] as String?)?.toLowerCase().contains(q) ?? false,
          )
          .toList();
    }

    if (widget.videos.isEmpty) {
      return const EmptyState(
        icon: Icons.movie_rounded,
        title: 'Aucune vidéo',
        message: 'Cet utilisateur n\'a pas encore publié de clip.',
      );
    }

    return Column(
      children: [
        // Filtres
        Row(
          children: [
            SizedBox(
              width: 200,
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Filtrer par titre…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('Tous')),
                ButtonSegment(value: 'published', label: Text('Publiés')),
                ButtonSegment(value: 'removed', label: Text('Retirés')),
              ],
              selected: {_statusFilter},
              onSelectionChanged: (v) =>
                  setState(() => _statusFilter = v.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStateProperty.all(theme.textTheme.labelSmall),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${filtered.length} clip(s)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'Space Mono',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final v = filtered[i];
              final status = v['status'] as String? ?? '?';
              final title = v['title'] as String? ?? 'Sans titre';
              final views = v['view_count'] as num? ?? 0;
              final likes = v['like_count'] as num? ?? 0;
              final comments = v['comment_count'] as num? ?? 0;
              final publishedAt = v['published_at'] as String?;
              final sizeBytes = v['size_bytes'] as num?;
              final duration = v['duration_seconds'] as num?;

              return ListTile(
                dense: true,
                leading: _StatusDot(status: status),
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  [
                    if (publishedAt != null)
                      '${DateTime.parse(publishedAt).day}/${DateTime.parse(publishedAt).month}',
                    if (sizeBytes != null)
                      '${(sizeBytes / 1048576).toStringAsFixed(1)} Mo',
                    if (duration != null) '${duration}s',
                    '$views vues · $likes likes · $comments com.',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'published' => const Color(0xFF059669),
      'removed' => const Color(0xFFDC2626),
      'rejected' => const Color(0xFFF59E0B),
      _ => const Color(0xFF6B7280),
    };

    return Tooltip(
      message: status,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Section Commentaires
// ═══════════════════════════════════════════════════════════════════════════

class _CommentsSection extends StatefulWidget {
  const _CommentsSection({required this.comments});

  final List<AdminUserComment> comments;

  @override
  State<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<_CommentsSection> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    var filtered = widget.comments;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered
          .where((c) => c.body.toLowerCase().contains(q))
          .toList();
    }

    if (widget.comments.isEmpty) {
      return const EmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Aucun commentaire',
        message: 'Cet utilisateur n\'a pas encore commenté.',
      );
    }

    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Rechercher dans les commentaires…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${filtered.length} / ${widget.comments.length}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'Space Mono',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = filtered[i];
              final isDeleted = c.deletedAt != null;
              return ListTile(
                dense: true,
                leading: Icon(
                  isDeleted
                      ? Icons.delete_outline_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: 18,
                  color: isDeleted
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(
                  c.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    decoration: isDeleted ? TextDecoration.lineThrough : null,
                    color: isDeleted
                        ? theme.colorScheme.onSurfaceVariant
                        : null,
                  ),
                ),
                subtitle: Text(
                  '${c.createdAt.day}/${c.createdAt.month}/${c.createdAt.year}'
                  '${isDeleted ? ' · Supprimé' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Section Playlists
// ═══════════════════════════════════════════════════════════════════════════

class _PlaylistsSection extends StatelessWidget {
  const _PlaylistsSection({required this.playlists});

  final List<AdminUserPlaylist> playlists;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (playlists.isEmpty) {
      return const EmptyState(
        icon: Icons.playlist_play_rounded,
        title: 'Aucune playlist',
        message: 'Cet utilisateur n\'a pas créé de playlist.',
      );
    }

    return ListView.separated(
      itemCount: playlists.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final p = playlists[i];
        return ListTile(
          dense: true,
          leading: Icon(
            p.isPublic ? Icons.public_rounded : Icons.lock_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(
            p.title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            '${p.itemCount} clip(s) · '
            '${p.isPublic ? "Publique" : "Privée"} · '
            '${p.createdAt.day}/${p.createdAt.month}/${p.createdAt.year}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Section Abonnements
// ═══════════════════════════════════════════════════════════════════════════

class _SubsSection extends StatefulWidget {
  const _SubsSection({
    required this.subscriptions,
    required this.subscribers,
    required this.detail,
  });

  final List<AdminUserSubscription> subscriptions;
  final List<AdminUserSubscriber> subscribers;
  final AdminUserDetail detail;

  @override
  State<_SubsSection> createState() => _SubsSectionState();
}

class _SubsSectionState extends State<_SubsSection> {
  bool _showSubscribers = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _showSubscribers ? widget.subscribers : widget.subscriptions;

    if (widget.subscriptions.isEmpty && widget.subscribers.isEmpty) {
      return const EmptyState(
        icon: Icons.people_outline_rounded,
        title: 'Aucun abonnement',
        message: 'Aucune activité d\'abonnement.',
      );
    }

    return Column(
      children: [
        Row(
          children: [
            ChoiceChip(
              label: Text('Abonnements (${widget.subscriptions.length})'),
              selected: !_showSubscribers,
              onSelected: (_) => setState(() => _showSubscribers = false),
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: Text('Abonnés (${widget.subscribers.length})'),
              selected: _showSubscribers,
              onSelected: (_) => setState(() => _showSubscribers = true),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (_showSubscribers) {
                final s = widget.subscribers[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.person_rounded, size: 18),
                  title: Text(
                    s.subscriberDisplayName ??
                        s.subscriberUsername ??
                        s.subscriberId,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${s.createdAt.day}/${s.createdAt.month}/${s.createdAt.year}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                );
              } else {
                final s = widget.subscriptions[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.favorite_border_rounded, size: 18),
                  title: Text(
                    s.artistDisplayName ?? s.artistUsername ?? s.artistId,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${s.createdAt.day}/${s.createdAt.month}/${s.createdAt.year}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Section Signalements
// ═══════════════════════════════════════════════════════════════════════════

class _ReportsSection extends StatefulWidget {
  const _ReportsSection({required this.filed, required this.against});

  final List<AdminUserReport> filed;
  final List<AdminUserReport> against;

  @override
  State<_ReportsSection> createState() => _ReportsSectionState();
}

class _ReportsSectionState extends State<_ReportsSection> {
  bool _showAgainst = false;
  String _statusFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _showAgainst ? widget.against : widget.filed;

    var filtered = list;
    if (_statusFilter != 'all') {
      filtered = filtered.where((r) => r.status == _statusFilter).toList();
    }

    if (widget.filed.isEmpty && widget.against.isEmpty) {
      return const EmptyState(
        icon: Icons.report_outlined,
        title: 'Aucun signalement',
        message: 'Aucune activité de signalement.',
      );
    }

    return Column(
      children: [
        Row(
          children: [
            ChoiceChip(
              label: Text('Émis (${widget.filed.length})'),
              selected: !_showAgainst,
              onSelected: (_) => setState(() => _showAgainst = false),
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: Text('Reçus (${widget.against.length})'),
              selected: _showAgainst,
              onSelected: (_) => setState(() => _showAgainst = true),
            ),
            const SizedBox(width: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('Tous')),
                ButtonSegment(value: 'pending', label: Text('En attente')),
                ButtonSegment(value: 'reviewed', label: Text('Traité')),
                ButtonSegment(value: 'dismissed', label: Text('Rejeté')),
              ],
              selected: {_statusFilter},
              onSelectionChanged: (v) =>
                  setState(() => _statusFilter = v.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStateProperty.all(theme.textTheme.labelSmall),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = filtered[i];
              final reasonLabel = _reportReasonLabel(r.reason);
              final statusColor = r.status == 'pending'
                  ? const Color(0xFFF59E0B)
                  : r.status == 'reviewed'
                  ? const Color(0xFF059669)
                  : theme.colorScheme.onSurfaceVariant;
              return ListTile(
                dense: true,
                leading: Icon(
                  Icons.report_rounded,
                  size: 18,
                  color: statusColor,
                ),
                title: Text(
                  '${r.targetKind == 'video' ? 'Clip' : 'Commentaire'} · $reasonLabel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${r.createdAt.day}/${r.createdAt.month}/${r.createdAt.year} · ${_statusLabel(r.status)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: statusColor,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

String _reportReasonLabel(String reason) {
  return switch (reason) {
    'spam' => 'Spam',
    'hate_speech' => 'Discours haineux',
    'sexual_content' => 'Contenu sexuel',
    'violence' => 'Violence',
    'copyright' => 'Droit d\'auteur',
    'misinformation' => 'Désinformation',
    'other' => 'Autre',
    _ => reason,
  };
}

String _statusLabel(String status) {
  return switch (status) {
    'pending' => 'En attente',
    'reviewed' => 'Traité',
    'dismissed' => 'Rejeté',
    _ => status,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// Section Journal de modération
// ═══════════════════════════════════════════════════════════════════════════

class _ModLogsSection extends StatelessWidget {
  const _ModLogsSection({required this.logs});

  final List<AdminUserModLog> logs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (logs.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_rounded,
        title: 'Aucune entrée',
        message: 'Aucune action de modération pour cet utilisateur.',
      );
    }

    return ListView.separated(
      itemCount: logs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final l = logs[i];
        final actionLabel = _actionLabel(l.action);
        return ListTile(
          dense: true,
          leading: Icon(
            l.actor == 'ai' ? Icons.smart_toy_rounded : Icons.shield_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(
            actionLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            '${l.createdAt.day}/${l.createdAt.month}/${l.createdAt.year} '
            '${l.createdAt.hour}h${l.createdAt.minute.toString().padLeft(2, '0')}'
            '${l.reason != null ? ' · ${l.reason}' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        );
      },
    );
  }
}

String _actionLabel(String action) {
  return switch (action) {
    'user_created' => 'Compte créé par un admin',
    'user_deleted' => 'Compte supprimé',
    'user_banned' => 'Compte banni',
    'user_unbanned' => 'Compte débanni',
    'role_changed_to_listener' => 'Rôle changé → Auditeur',
    'role_changed_to_artist' => 'Rôle changé → Artiste',
    'role_changed_to_admin' => 'Rôle changé → Admin',
    'application_approved' => 'Candidature approuvée',
    'application_rejected' => 'Candidature rejetée',
    'video_published' => 'Clip publié',
    'reject_video' => 'Clip rejeté',
    'remove_video' => 'Clip retiré',
    'remove_comment' => 'Commentaire retiré',
    'report_dismissed' => 'Signalement rejeté',
    'warn_author' => 'Auteur averti',
    _ => action,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// Badge de rôle (copie locale pour éviter l'import du fichier parent)
// ═══════════════════════════════════════════════════════════════════════════

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }
}
