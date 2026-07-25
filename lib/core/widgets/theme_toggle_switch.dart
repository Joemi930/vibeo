import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../theme/theme_mode_provider.dart';

/// Interrupteur glissant clair ↔ sombre, présent dans la barre de chaque écran.
///
/// Évite d'ouvrir les Paramètres pour changer de thème. Le choix « Système »
/// reste disponible dans les Paramètres : un interrupteur à deux positions ne
/// peut pas l'exprimer.
///
/// S'appuie sur [themeModeProvider] : la persistance (SharedPreferences) est
/// donc déjà assurée, rien de nouveau côté état.
class ThemeToggleSwitch extends ConsumerWidget {
  const ThemeToggleSwitch({super.key});

  static const double _width = 52;
  static const double _height = 30;
  static const double _knob = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final isDark = _isDark(context, mode);
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      toggled: isDark,
      label: 'Thème sombre',
      child: Tooltip(
        message: isDark ? 'Passer en thème clair' : 'Passer en thème sombre',
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => ref
              .read(themeModeProvider.notifier)
              .setMode(isDark ? ThemeMode.light : ThemeMode.dark),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: _width,
              height: _height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: scheme.outlineVariant),
                color: isDark ? scheme.surfaceContainerHighest : null,
                gradient: isDark ? null : VibeoColors.of(context).gradient,
              ),
              child: Stack(
                children: [
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: isDark
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Container(
                        width: _knob,
                        height: _knob,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark ? scheme.surface : Colors.white,
                        ),
                        child: Icon(
                          isDark
                              ? Icons.dark_mode_rounded
                              : Icons.light_mode_rounded,
                          size: 15,
                          color: isDark ? scheme.onSurface : scheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Luminosité réellement affichée : en mode « système », on interroge la
  /// préférence de la plateforme pour savoir vers quoi basculer.
  static bool _isDark(BuildContext context, ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
  }
}
