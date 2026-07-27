import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/admin_video_queue.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_data_table.dart';
import '../widgets/confirm_action_dialog.dart';

/// Onglet « Modération vidéos » du dashboard admin.
///
/// Table des clips en attente d'une décision, avec badge de statut et actions
/// Publier / Rejeter / Retirer. Les actions passent par l'Edge Function
/// `admin-actions` et invalident la file après exécution.
class VideoModerationTab extends ConsumerWidget {
  const VideoModerationTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(adminVideoQueueProvider);

    return queueAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ErrorState(
        message: 'Impossible de charger la file de modération.',
        onRetry: () => ref.invalidate(adminVideoQueueProvider),
      ),
      data: (queue) {
        if (queue.isEmpty) {
          return const EmptyState(
            icon: Icons.reviews_rounded,
            title: 'File de modération vide',
            message: 'Tous les clips ont été traités. Aucun en attente.',
          );
        }
        return Padding(
          padding: const EdgeInsets.all(20),
          child: _VideoTable(queue: queue),
        );
      },
    );
  }
}

class _VideoTable extends ConsumerWidget {
  const _VideoTable({required this.queue});

  final List<AdminVideoQueueItem> queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columns = const [
      ColumnDef(label: 'Titre', flex: 1.8),
      ColumnDef(label: 'Artiste', flex: 1.2),
      ColumnDef(label: 'Date', flex: 1.0),
      ColumnDef(label: 'Statut', flex: 1.0),
      ColumnDef(label: 'Actions', flex: 1.5, alignment: Alignment.centerRight),
    ];

    final rows = <List<Widget>>[];
    for (final item in queue) {
      rows.add([
        // Titre
        Text(
          item.title,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),

        // Artiste
        Text(
          item.resolvedArtistName,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),

        // Date
        Text(
          _formatDate(item.createdAt),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),

        // Statut
        StatusBadge(status: item.status),

        // Actions
        Builder(
          builder: (rowContext) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.status.isPublished)
                  OutlinedButton.icon(
                    onPressed: () =>
                        _showActionDialog(rowContext, ref, item, 'removed'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(rowContext).colorScheme.error,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    icon: const Icon(Icons.block_rounded, size: 16),
                    label: const Text('Retirer'),
                  )
                else ...[
                  if (item.status.value == 'pending_moderation') ...[
                    FilledButton(
                      onPressed: () =>
                          _showActionDialog(rowContext, ref, item, 'published'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 36),
                      ),
                      child: const Text('Publier'),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton(
                      onPressed: () =>
                          _showActionDialog(rowContext, ref, item, 'rejected'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(rowContext).colorScheme.error,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 36),
                      ),
                      child: const Text('Rejeter'),
                    ),
                  ] else
                    Text(
                      item.status.label,
                      style: Theme.of(rowContext).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          rowContext,
                        ).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ]);
    }

    return AdminDataTable(
      columns: columns,
      rows: rows,
      emptyMessage: 'Aucun clip en attente.',
    );
  }

  Future<void> _showActionDialog(
    BuildContext context,
    WidgetRef ref,
    AdminVideoQueueItem item,
    String decision,
  ) async {
    final isRemoval = decision == 'removed';

    final result = await showConfirmActionDialog(
      context: context,
      title: switch (decision) {
        'published' => 'Publier ce clip ?',
        'rejected' => 'Rejeter ce clip ?',
        _ => 'Retirer ce clip ?',
      },
      message: switch (decision) {
        'published' => '« ${item.title} » sera visible publiquement.',
        'rejected' => 'L\'artiste verra le motif de refus dans son Studio.',
        _ =>
          '« ${item.title} » ne sera plus visible. Cette action est réversible.',
      },
      confirmLabel: switch (decision) {
        'published' => 'Publier',
        'rejected' => 'Rejeter',
        _ => 'Retirer',
      },
      isDestructive: isRemoval || decision == 'rejected',
      requireReason: decision != 'published',
      reasonLabel: 'Motif',
      reasonHint: decision == 'rejected'
          ? 'Explique pourquoi ce clip est refusé…'
          : 'Motif du retrait',
    );

    if (!result.confirmed || !context.mounted) return;

    final error = await ref
        .read(adminActionControllerProvider.notifier)
        .moderateVideo(
          videoId: item.id,
          decision: decision,
          reason: result.reason.isNotEmpty ? result.reason : null,
        );
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays == 0) return 'Aujourd\'hui';
    if (diff.inDays == 1) return 'Hier';
    if (diff.inDays < 7) return 'il y a ${diff.inDays} j';
    if (diff.inDays < 30) return 'il y a ${(diff.inDays / 7).floor()} sem.';
    final months = (diff.inDays / 30).floor();
    return 'il y a $months mois';
  }
}
