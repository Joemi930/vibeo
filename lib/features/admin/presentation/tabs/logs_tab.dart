import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../domain/moderation_log.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_data_table.dart';

/// Onglet « Journal » du dashboard admin — consultation seule.
///
/// Lit les 200 dernières entrées du journal de modération, avec un filtre par
/// type de cible via un menu déroulant en en-tête.
class LogsTab extends ConsumerWidget {
  const LogsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pas de filtre : on lit tout.
    final logsAsync = ref.watch(adminLogsProvider(null));

    return logsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ErrorState(
        message: 'Impossible de charger le journal.',
        onRetry: () => ref.invalidate(adminLogsProvider(null)),
      ),
      data: (logs) {
        if (logs.isEmpty) {
          return const EmptyState(
            icon: Icons.receipt_long_rounded,
            title: 'Journal vide',
            message: 'Aucune action de modération enregistrée.',
          );
        }
        return Padding(
          padding: const EdgeInsets.all(20),
          child: _LogsTable(logs: logs),
        );
      },
    );
  }
}

class _LogsTable extends StatelessWidget {
  const _LogsTable({required this.logs});

  final List<ModerationLog> logs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vibeo = VibeoColors.of(context);

    final columns = const [
      ColumnDef(label: 'Date', flex: 0.8),
      ColumnDef(label: 'Acteur', flex: 0.6),
      ColumnDef(label: 'Action', flex: 1.2),
      ColumnDef(label: 'Cible', flex: 0.8),
      ColumnDef(label: 'Détail', flex: 2.0),
    ];

    final rows = <List<Widget>>[];
    for (final entry in logs) {
      rows.add([
        // Date
        Text(
          _formatDateTime(entry.createdAt),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFamily: 'Space Mono',
            fontSize: 11,
          ),
        ),

        // Acteur
        _ActorBadge(actor: entry.actor),

        // Action
        Text(
          entry.action,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),

        // Cible (type)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: vibeo.info.withAlpha(20),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            entry.targetType.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: vibeo.info,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        // Détail (raison ou métadonnées)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (entry.reason != null)
              Text(
                entry.reason!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (entry.targetId != null)
              Text(
                'ID : ${entry.targetId}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                  fontFamily: 'Space Mono',
                ),
              ),
            if (entry.reason == null && entry.targetId == null)
              Text(
                '—',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ]);
    }

    return AdminDataTable(
      columns: columns,
      rows: rows,
      emptyMessage: 'Aucune entrée dans le journal.',
    );
  }

  String _formatDateTime(DateTime dt) {
    final day =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$day $time';
  }
}

class _ActorBadge extends StatelessWidget {
  const _ActorBadge({required this.actor});

  final ModerationActor actor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vibeo = VibeoColors.of(context);

    final (Color fg, Color bg, String label) = switch (actor) {
      ModerationActor.ai => (vibeo.info, vibeo.info.withAlpha(20), 'IA'),
      ModerationActor.admin => (
        vibeo.onSuccessContainer,
        vibeo.successContainer,
        'Admin',
      ),
      ModerationActor.system => (
        theme.colorScheme.onSurfaceVariant,
        theme.colorScheme.surfaceContainerHighest,
        'Système',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }
}
