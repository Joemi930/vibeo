import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../domain/admin_report.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_data_table.dart';
import '../widgets/confirm_action_dialog.dart';

/// Onglet « Signalements » du dashboard admin.
///
/// Table triée par `priority desc`, avec actions Voir / Ignorer / Traiter.
class ReportsTab extends ConsumerWidget {
  const ReportsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(adminReportsProvider);

    return reportsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ErrorState(
        message: 'Impossible de charger les signalements.',
        onRetry: () => ref.invalidate(adminReportsProvider),
      ),
      data: (reports) {
        if (reports.isEmpty) {
          return const EmptyState(
            icon: Icons.report_rounded,
            title: 'Aucun signalement',
            message: 'La plateforme est propre. Aucun contenu signalé.',
          );
        }
        return Padding(
          padding: const EdgeInsets.all(20),
          child: _ReportsTable(reports: reports),
        );
      },
    );
  }
}

class _ReportsTable extends ConsumerWidget {
  const _ReportsTable({required this.reports});

  final List<AdminReport> reports;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final columns = const [
      ColumnDef(label: 'Motif', flex: 1.4),
      ColumnDef(label: 'Cible', flex: 1.6),
      ColumnDef(label: 'Signalé par', flex: 1.2),
      ColumnDef(label: 'Priorité', flex: 0.6),
      ColumnDef(label: 'Statut', flex: 0.8),
      ColumnDef(label: 'Actions', flex: 1.2, alignment: Alignment.centerRight),
    ];

    final rows = <List<Widget>>[];
    for (final report in reports) {
      rows.add([
        // Motif
        Row(
          children: [
            _ReasonIcon(reason: report.reason),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                report.reason.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),

        // Cible
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              report.videoTitle ?? report.commentContent ?? 'Cible inconnue',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              report.targetKind.value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),

        // Signalé par
        Text(
          report.reporterUsername ?? 'Anonyme',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),

        // Priorité
        _PriorityBadge(priority: report.priority),

        // Statut
        _ReportStatusBadge(status: report.status),

        // Actions
        Builder(
          builder: (rowContext) {
            if (report.status != ReportStatus.pending) {
              return Text(
                report.status.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              );
            }
            return Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: () =>
                      _resolveReport(rowContext, ref, report, 'remove_content'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 36),
                  ),
                  child: const Text('Retirer'),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  onPressed: () =>
                      _resolveReport(rowContext, ref, report, 'dismiss'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 36),
                  ),
                  child: const Text('Ignorer'),
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
      emptyMessage: 'Aucun signalement.',
    );
  }

  Future<void> _resolveReport(
    BuildContext context,
    WidgetRef ref,
    AdminReport report,
    String resolution,
  ) async {
    final isDismiss = resolution == 'dismiss';

    final result = await showConfirmActionDialog(
      context: context,
      title: isDismiss ? 'Ignorer ce signalement ?' : 'Retirer ce contenu ?',
      message: isDismiss
          ? 'Le contenu restera visible et le signalement sera marqué comme rejeté.'
          : 'Le contenu signalé sera retiré de la plateforme.',
      confirmLabel: isDismiss ? 'Ignorer' : 'Retirer le contenu',
      isDestructive: !isDismiss,
      requireReason: true,
      reasonLabel: isDismiss ? 'Justification' : 'Motif du retrait',
    );

    if (!result.confirmed || !context.mounted) return;

    final error = await ref
        .read(adminActionControllerProvider.notifier)
        .resolveReport(
          reportId: report.id,
          resolution: resolution,
          reason: result.reason,
        );
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

class _ReasonIcon extends StatelessWidget {
  const _ReasonIcon({required this.reason});

  final ReportReason reason;

  @override
  Widget build(BuildContext context) {
    final vibeo = VibeoColors.of(context);
    final icon = switch (reason) {
      ReportReason.spam => Icons.mark_email_unread_rounded,
      ReportReason.hateSpeech => Icons.front_hand_rounded,
      ReportReason.sexualContent => Icons.no_adult_content_rounded,
      ReportReason.violence => Icons.dangerous_rounded,
      ReportReason.copyright => Icons.copyright_rounded,
      ReportReason.misinformation => Icons.error_outline_rounded,
      ReportReason.other => Icons.flag_rounded,
    };
    return Icon(icon, size: 18, color: vibeo.warning);
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});

  final int priority;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vibeo = VibeoColors.of(context);
    final Color color = priority >= 8
        ? theme.colorScheme.error
        : priority >= 5
        ? vibeo.warning
        : vibeo.success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$priority',
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontFamily: 'Space Mono',
        ),
      ),
    );
  }
}

class _ReportStatusBadge extends StatelessWidget {
  const _ReportStatusBadge({required this.status});

  final ReportStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vibeo = VibeoColors.of(context);

    final (Color fg, Color bg) = switch (status) {
      ReportStatus.pending => (vibeo.warning, vibeo.warningContainer),
      ReportStatus.reviewed => (
        vibeo.onSuccessContainer,
        vibeo.successContainer,
      ),
      ReportStatus.dismissed => (
        theme.colorScheme.onSurfaceVariant,
        theme.colorScheme.surfaceContainerHighest,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
