import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../profile/presentation/providers/profile_providers.dart';
import 'providers/admin_providers.dart';
import 'tabs/applications_tab.dart';
import 'tabs/logs_tab.dart';
import 'tabs/reports_tab.dart';
import 'tabs/stats_tab.dart';
import 'tabs/video_moderation_tab.dart';
import 'widgets/storage_gauge.dart';

/// Coque de navigation du dashboard d'administration.
///
/// Barre latérale 230 px à partir de 1000 px, [Drawer] en dessous. L'onglet
/// courant est dérivé du paramètre de requête `?tab=`.
///
/// La garde d'authentification est traitée par le routeur ; `AdminShell` ne
/// fait que vérifier le profil pour afficher le dashboard ou un refus.
class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  late AdminTab _currentTab;

  @override
  void initState() {
    super.initState();
    _syncTabFromUri();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTabFromUri();
  }

  void _syncTabFromUri() {
    final uri = GoRouterState.of(context).uri;
    _currentTab = AdminTab.fromString(uri.queryParameters['tab']);
  }

  void _switchTab(AdminTab tab) {
    setState(() => _currentTab = tab);
    // Met à jour l'URL sans recharger la page.
    GoRouter.of(context).replace('/admin?tab=${tab.value}');

    // Ferme le panneau d'examen quand on change d'onglet.
    ref.read(selectedApplicationProvider.notifier).close();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(currentProfileProvider);
    final isAdmin = ref.watch(isAdminProvider);

    return Scaffold(
      drawer: _AdminDrawer(currentTab: _currentTab, onTabSelected: _switchTab),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Impossible de vérifier les droits d\'accès.'),
        ),
        data: (_) {
          if (!isAdmin) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.admin_panel_settings_rounded,
                      size: 64,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Accès réservé à l\'administration',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Cette section est strictement réservée aux '
                      'administrateurs de la plateforme.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final showSidebar = constraints.maxWidth >= 1000;
              return Row(
                children: [
                  if (showSidebar)
                    _AdminSidebar(
                      currentTab: _currentTab,
                      onTabSelected: _switchTab,
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        // En-tête
                        if (!showSidebar)
                          _MobileHeader(
                            currentTab: _currentTab,
                            onMenuTap: () => Scaffold.of(context).openDrawer(),
                          ),
                        // Corps de l'onglet
                        Expanded(child: _buildTab(_currentTab)),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTab(AdminTab tab) {
    return switch (tab) {
      AdminTab.applications => const ApplicationsTab(),
      AdminTab.moderation => const VideoModerationTab(),
      AdminTab.reports => const ReportsTab(),
      AdminTab.stats => const StatsTab(),
      AdminTab.logs => const LogsTab(),
    };
  }
}

/// Helper : extrait un compteur d'un [AsyncValue] de stats.
int? _queueCount<T>(AsyncValue<T> asyncStats, int Function(T) selector) {
  final data = asyncStats.asData?.value;
  return data != null ? selector(data) : null;
}

/// Barre latérale fixe (>= 1000 px).
class _AdminSidebar extends ConsumerWidget {
  const _AdminSidebar({required this.currentTab, required this.onTabSelected});

  final AdminTab currentTab;
  final void Function(AdminTab) onTabSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final vibeo = VibeoColors.of(context);
    final statsAsync = ref.watch(adminStatsProvider);

    return Container(
      width: 230,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        children: [
          // Logo + badge ADMIN
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 22, 14, 0),
            child: Row(
              children: [
                Icon(Icons.equalizer_rounded, size: 24, color: vibeo.verified),
                const SizedBox(width: 9),
                Text(
                  'Vibeo',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.02,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'ADMIN',
                    style: TextStyle(
                      fontFamily: 'Space Mono',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Divider(
            color: theme.colorScheme.outlineVariant,
            indent: 22,
            endIndent: 22,
          ),
          const SizedBox(height: 8),

          // Navigation
          _NavItem(
            icon: Icons.how_to_reg_rounded,
            label: 'Candidatures',
            isSelected: currentTab == AdminTab.applications,
            badge: _queueCount(statsAsync, (s) => s.applicationQueueCount),
            onTap: () => onTabSelected(AdminTab.applications),
          ),
          _NavItem(
            icon: Icons.reviews_rounded,
            label: 'Modération vidéos',
            isSelected: currentTab == AdminTab.moderation,
            badge: _queueCount(statsAsync, (s) => s.moderationQueueCount),
            onTap: () => onTabSelected(AdminTab.moderation),
          ),
          _NavItem(
            icon: Icons.report_rounded,
            label: 'Signalements',
            isSelected: currentTab == AdminTab.reports,
            badge: _queueCount(statsAsync, (s) => s.openReportCount),
            onTap: () => onTabSelected(AdminTab.reports),
          ),
          _NavItem(
            icon: Icons.bar_chart_rounded,
            label: 'Statistiques',
            isSelected: currentTab == AdminTab.stats,
            onTap: () => onTabSelected(AdminTab.stats),
          ),
          _NavItem(
            icon: Icons.receipt_long_rounded,
            label: 'Journal',
            isSelected: currentTab == AdminTab.logs,
            onTap: () => onTabSelected(AdminTab.logs),
          ),

          const Spacer(),

          // Jauge de stockage
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
            child: statsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (stats) => StorageGauge(
                bytesUsed: stats.storageBytesUsed,
                bytesLimit: stats.storageBytesLimit,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Version Drawer pour les écrans étroits (< 1000 px).
class _AdminDrawer extends ConsumerWidget {
  const _AdminDrawer({required this.currentTab, required this.onTabSelected});

  final AdminTab currentTab;
  final void Function(AdminTab) onTabSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final vibeo = VibeoColors.of(context);
    final statsAsync = ref.watch(adminStatsProvider);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // En-tête
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Row(
                children: [
                  Icon(
                    Icons.equalizer_rounded,
                    size: 24,
                    color: vibeo.verified,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    'Vibeo',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      'ADMIN',
                      style: TextStyle(
                        fontFamily: 'Space Mono',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: theme.colorScheme.outlineVariant),

            // Navigation
            _NavItem(
              icon: Icons.how_to_reg_rounded,
              label: 'Candidatures',
              isSelected: currentTab == AdminTab.applications,
              badge: _queueCount(statsAsync, (s) => s.applicationQueueCount),
              onTap: () {
                onTabSelected(AdminTab.applications);
                Navigator.pop(context);
              },
            ),
            _NavItem(
              icon: Icons.reviews_rounded,
              label: 'Modération vidéos',
              isSelected: currentTab == AdminTab.moderation,
              badge: _queueCount(statsAsync, (s) => s.moderationQueueCount),
              onTap: () {
                onTabSelected(AdminTab.moderation);
                Navigator.pop(context);
              },
            ),
            _NavItem(
              icon: Icons.report_rounded,
              label: 'Signalements',
              isSelected: currentTab == AdminTab.reports,
              badge: _queueCount(statsAsync, (s) => s.openReportCount),
              onTap: () {
                onTabSelected(AdminTab.reports);
                Navigator.pop(context);
              },
            ),
            _NavItem(
              icon: Icons.bar_chart_rounded,
              label: 'Statistiques',
              isSelected: currentTab == AdminTab.stats,
              onTap: () {
                onTabSelected(AdminTab.stats);
                Navigator.pop(context);
              },
            ),
            _NavItem(
              icon: Icons.receipt_long_rounded,
              label: 'Journal',
              isSelected: currentTab == AdminTab.logs,
              onTap: () {
                onTabSelected(AdminTab.logs);
                Navigator.pop(context);
              },
            ),

            const Spacer(),

            // Jauge de stockage
            Padding(
              padding: const EdgeInsets.all(16),
              child: statsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (stats) => StorageGauge(
                  bytesUsed: stats.storageBytesUsed,
                  bytesLimit: stats.storageBytesLimit,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// En-tête mobile avec icône hamburger et titre de l'onglet.
class _MobileHeader extends StatelessWidget {
  const _MobileHeader({required this.currentTab, required this.onMenuTap});

  final AdminTab currentTab;
  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 16, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onMenuTap,
            icon: const Icon(Icons.menu_rounded),
            tooltip: 'Menu',
          ),
          const SizedBox(width: 4),
          Text(
            _tabTitle(currentTab),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.01,
            ),
          ),
        ],
      ),
    );
  }

  String _tabTitle(AdminTab tab) {
    return switch (tab) {
      AdminTab.applications => 'Candidatures artistes',
      AdminTab.moderation => 'Modération vidéos',
      AdminTab.reports => 'Signalements',
      AdminTab.stats => 'Statistiques',
      AdminTab.logs => 'Journal',
    };
  }
}

/// Élément du menu latéral — icône, libellé, badge (compteur), surbrillance.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1.5),
      child: Material(
        color: isSelected
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: isSelected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (badge != null)
                  _Badge(count: badge!, isSelected: isSelected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.isSelected});

  final int count;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasErrorContext = !isSelected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: hasErrorContext
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.primary.withAlpha(80),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontFamily: 'Space Mono',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: hasErrorContext
              ? theme.colorScheme.error
              : theme.colorScheme.onPrimary,
        ),
      ),
    );
  }
}
