import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../artist/domain/application_status.dart';
import '../../domain/admin_application.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_data_table.dart';
import '../widgets/review_panel.dart';

/// Onglet « Candidatures » du dashboard admin.
///
/// Affiche la table des candidatures artistes et, lorsqu'une ligne est
/// sélectionnée, le panneau d'examen [ReviewPanel] en volet droit.
class ApplicationsTab extends ConsumerWidget {
  const ApplicationsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applicationsAsync = ref.watch(adminApplicationsProvider);
    final selectedId = ref.watch(selectedApplicationProvider);

    return applicationsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ErrorState(
        message: 'Impossible de charger les candidatures.',
        onRetry: () => ref.invalidate(adminApplicationsProvider),
      ),
      data: (applications) {
        final selectedApp = selectedId != null
            ? applications.where((a) => a.id == selectedId).firstOrNull
            : null;

        return Row(
          children: [
            // Table
            Expanded(
              child: applications.isEmpty
                  ? EmptyState(
                      icon: Icons.how_to_reg_rounded,
                      title: 'Aucune candidature',
                      message: 'Les demandes de vérification apparaîtront ici.',
                    )
                  : _ApplicationsTable(
                      applications: applications,
                      selectedId: selectedId,
                    ),
            ),

            // Panneau d'examen
            if (selectedApp != null)
              ReviewPanel(
                application: selectedApp,
                onClose: () =>
                    ref.read(selectedApplicationProvider.notifier).close(),
              ),
          ],
        );
      },
    );
  }
}

class _ApplicationsTable extends ConsumerWidget {
  const _ApplicationsTable({
    required this.applications,
    required this.selectedId,
  });

  final List<AdminApplication> applications;
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final columns = const [
      ColumnDef(label: 'Artiste', flex: 1.6),
      ColumnDef(label: 'Date', flex: 1.0),
      ColumnDef(label: 'Statut', flex: 1.0),
      ColumnDef(label: 'Actions', flex: 1.5, alignment: Alignment.centerRight),
    ];

    final selectedIndex = selectedId != null
        ? applications.indexWhere((a) => a.id == selectedId)
        : -1;

    final rows = <List<Widget>>[];
    for (final app in applications) {
      final isPending = app.status.isOpen;

      rows.add([
        // Colonne Artiste
        Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                app.resolvedName.isNotEmpty
                    ? app.resolvedName[0].toUpperCase()
                    : '?',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    app.resolvedName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '@${app.username}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),

        // Colonne Date
        Text(
          _formatDate(app.createdAt),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),

        // Colonne Statut
        _StatusBadge(status: app.status),

        // Colonne Actions
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPending)
              Builder(
                builder: (ctx) {
                  final isCurrent =
                      app.id == ref.watch(selectedApplicationProvider);
                  if (isCurrent) {
                    return FilledButton.tonal(
                      onPressed: null,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                      ),
                      child: const Text('En cours'),
                    );
                  }
                  return OutlinedButton(
                    onPressed: () => ref
                        .read(selectedApplicationProvider.notifier)
                        .select(app.id),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                    ),
                    child: const Text('Examiner'),
                  );
                },
              )
            else
              Text(
                app.status.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ]);
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: AdminDataTable(
        columns: columns,
        rows: rows,
        selectedIndex: selectedIndex >= 0 ? selectedIndex : null,
        onRowTap: (index) {
          ref
              .read(selectedApplicationProvider.notifier)
              .select(applications[index].id);
        },
        emptyMessage: 'Aucune candidature.',
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Aujourd\'hui';
    if (diff.inDays == 1) return 'Hier';
    if (diff.inDays < 7) return 'il y a ${diff.inDays} j';
    if (diff.inDays < 30) return 'il y a ${(diff.inDays / 7).floor()} sem.';
    final months = (diff.inDays / 30).floor();
    return 'il y a $months mois';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ApplicationStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vibeo = VibeoColors.of(context);

    final (Color fg, Color bg, IconData icon) = switch (status) {
      ApplicationStatus.pending => (
        vibeo.warning,
        vibeo.warningContainer,
        Icons.schedule_rounded,
      ),
      ApplicationStatus.manualReview => (
        vibeo.info,
        theme.colorScheme.surfaceContainerHighest,
        Icons.visibility_rounded,
      ),
      ApplicationStatus.approved => (
        vibeo.onSuccessContainer,
        vibeo.successContainer,
        Icons.check_circle_rounded,
      ),
      ApplicationStatus.rejected => (
        theme.colorScheme.onErrorContainer,
        theme.colorScheme.errorContainer,
        Icons.cancel_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
