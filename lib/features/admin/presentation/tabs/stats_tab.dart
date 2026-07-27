import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../core/widgets/error_state.dart';
import '../providers/admin_providers.dart';
import '../widgets/storage_gauge.dart';

/// Onglet « Statistiques » du dashboard admin.
///
/// Trois cartes (utilisateurs, vidéos, vues) + jauge de stockage.
class StatsTab extends ConsumerWidget {
  const StatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(adminStatsProvider);
    final theme = Theme.of(context);
    final vibeo = VibeoColors.of(context);

    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ErrorState(
        message: 'Impossible de charger les statistiques.',
        onRetry: () => ref.invalidate(adminStatsProvider),
      ),
      data: (stats) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Trois cartes statistiques
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon: Icons.group_rounded,
                      label: 'Utilisateurs',
                      value: formatGroupedCount(stats.userCount),
                      detail:
                          '${formatGroupedCount(stats.artistCount)} artistes vérifiés',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.movie_rounded,
                      label: 'Vidéos publiées',
                      value: formatGroupedCount(stats.publishedVideoCount),
                      detail:
                          '${formatGroupedCount(stats.moderationQueueCount)} en modération',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.visibility_rounded,
                      label: 'Vues totales',
                      value: formatCompactCount(stats.totalViewCount),
                      detail:
                          '${formatGroupedCount(stats.openReportCount)} signalements ouverts',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Jauge de stockage
              Text(
                'Stockage',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              StorageGauge(
                bytesUsed: stats.storageBytesUsed,
                bytesLimit: stats.storageBytesLimit,
              ),

              const SizedBox(height: 24),

              // Détail en attente
              _buildQueueSection(context, ref, stats, vibeo),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQueueSection(
    BuildContext context,
    WidgetRef ref,
    dynamic stats,
    VibeoColors vibeo,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'En attente',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          _QueueRow(
            icon: Icons.how_to_reg_rounded,
            label: 'Candidatures',
            count: stats.applicationQueueCount,
            color: vibeo.info,
          ),
          const SizedBox(height: 10),
          _QueueRow(
            icon: Icons.reviews_rounded,
            label: 'Clips à modérer',
            count: stats.moderationQueueCount,
            color: vibeo.warning,
          ),
          const SizedBox(height: 10),
          _QueueRow(
            icon: Icons.report_rounded,
            label: 'Signalements',
            count: stats.openReportCount,
            color: theme.colorScheme.error,
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vibeo = VibeoColors.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: vibeo.info),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.02,
              ),
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: vibeo.success,
                fontSize: 11.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            formatGroupedCount(count),
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontFamily: 'Space Mono',
            ),
          ),
        ),
      ],
    );
  }
}
