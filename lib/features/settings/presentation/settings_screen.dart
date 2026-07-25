import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../core/widgets/vibeo_app_bar.dart';
import '../../auth/presentation/providers/auth_controller.dart';
import '../../auth/presentation/providers/guest_mode_provider.dart';

/// Écran Paramètres : apparence (thème), compte, déconnexion, zone de danger.
/// Fidèle à `Maquettes/Settings.dc.html`.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: const VibeoAppBar(title: 'Paramètres'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _SectionLabel('Apparence'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ThemeVignette(
                  label: 'Sombre',
                  brightness: Brightness.dark,
                  selected: mode == ThemeMode.dark,
                  onTap: () => ref
                      .read(themeModeProvider.notifier)
                      .setMode(ThemeMode.dark),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ThemeVignette(
                  label: 'Clair',
                  brightness: Brightness.light,
                  selected: mode == ThemeMode.light,
                  onTap: () => ref
                      .read(themeModeProvider.notifier)
                      .setMode(ThemeMode.light),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ThemeVignette(
                  label: 'Système',
                  brightness: null,
                  selected: mode == ThemeMode.system,
                  onTap: () => ref
                      .read(themeModeProvider.notifier)
                      .setMode(ThemeMode.system),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _SectionLabel('Compte'),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                _AccountTile(
                  icon: Icons.person_rounded,
                  label: 'Infos du profil',
                  onTap: () => context.go(AppRoutes.profile),
                ),
                const Divider(height: 1),
                _AccountTile(
                  icon: Icons.notifications_rounded,
                  label: 'Notifications',
                  enabled: false,
                ),
                const Divider(height: 1),
                _AccountTile(
                  icon: Icons.lock_rounded,
                  label: 'Confidentialité',
                  enabled: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _confirmSignOut(context, ref),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Se déconnecter'),
          ),
          const SizedBox(height: 28),
          _SectionLabel('Zone de danger', color: theme.colorScheme.error),
          const SizedBox(height: 12),
          _DangerZone(),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Se déconnecter'),
        content: const Text('Veux-tu vraiment te déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      // On efface aussi le mode invité : sans ça, la déconnexion renverrait
      // vers l'accueil en consultation libre au lieu de l'écran de connexion.
      await ref.read(guestModeProvider.notifier).disable();
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelMedium?.copyWith(
        color: color ?? theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.04 * 14,
      ),
    );
  }
}

/// Vignette d'aperçu d'un thème (sombre / clair / système).
class _ThemeVignette extends StatelessWidget {
  const _ThemeVignette({
    required this.label,
    required this.brightness,
    required this.selected,
    required this.onTap,
  });

  final String label;

  /// `null` = système (aperçu mi-sombre mi-clair).
  final Brightness? brightness;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Container(
            height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
                width: selected ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: _preview(),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview() {
    const dark = Color(0xFF121016);
    const light = Color(0xFFFAF9FC);
    const accent = Color(0xFF7C3AED);
    if (brightness == null) {
      return Stack(
        children: [
          Row(
            children: const [
              Expanded(child: ColoredBox(color: dark)),
              Expanded(child: ColoredBox(color: light)),
            ],
          ),
          const Positioned(top: 20, left: 8, child: _Swatch(color: accent)),
        ],
      );
    }
    final isDark = brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: isDark ? dark : light)),
        Positioned(
          top: 8,
          left: 8,
          right: 24,
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2E2836) : const Color(0xFFE9E4F3),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        Positioned(
          top: 20,
          left: 8,
          child: _Swatch(color: isDark ? accent : const Color(0xFF6C3BD9)),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.icon,
    required this.label,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      enabled: enabled,
      leading: Icon(icon, color: theme.colorScheme.tertiary),
      title: Text(label),
      trailing: enabled
          ? const Icon(Icons.chevron_right_rounded)
          : Text(
              'Bientôt',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      onTap: enabled ? onTap : null,
    );
  }
}

class _DangerZone extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        border: Border.all(color: error),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Supprimer mon compte',
            style: theme.textTheme.titleSmall?.copyWith(
              color: error,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Action définitive : tes clips, playlists et abonnés seront supprimés.',
            style: theme.textTheme.bodySmall?.copyWith(color: error),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'La suppression de compte arrivera prochainement.',
                  ),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: error,
              side: BorderSide(color: error),
            ),
            child: const Text('Supprimer le compte'),
          ),
        ],
      ),
    );
  }
}
