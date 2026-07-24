import 'package:flutter/material.dart';

/// Jetons de couleur bruts du design system Vibeo (voir `Maquettes/README.md`).
///
/// Ces constantes ne sont utilisées QUE pour construire les thèmes
/// (`app_theme.dart`). Dans le reste de l'app, on passe toujours par
/// `Theme.of(context).colorScheme` ou l'extension [VibeoColors] — jamais de
/// couleur en dur.
class AppColors {
  const AppColors._();

  // Dégradé signature (identique clair/sombre) — réservé aux CTA forts.
  static const Color gradientStart = Color(0xFF7C3AED);
  static const Color gradientEnd = Color(0xFF4F46E5);
  static const LinearGradient signatureGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientEnd],
  );

  // --- Mode sombre (défaut) ---
  static const Color dBg = Color(0xFF121016);
  static const Color dSurface1 = Color(0xFF1B1820);
  static const Color dSurface2 = Color(0xFF241F2B);
  static const Color dSurface3 = Color(0xFF2E2836);
  static const Color dPrimary = Color(0xFF7C3AED);
  static const Color dPrimaryVariant = Color(0xFF8B5CF6);
  static const Color dContainer = Color(0xFF35216B);
  static const Color dOnContainer = Color(0xFFE9DDFF);
  static const Color dAccent = Color(0xFFB69DF8);
  static const Color dTextPrimary = Color(0xFFF4F1F8);
  static const Color dTextSecondary = Color(0xFFB9B2C7);
  static const Color dTextTertiary = Color(0xFF7C7589);
  static const Color dBorder = Color(0xFF322C3D);
  static const Color dSuccess = Color(0xFF4ADE80);
  static const Color dSuccessBg = Color(0xFF12301F);
  static const Color dWarning = Color(0xFFFBBF24);
  static const Color dWarningBg = Color(0xFF33270A);
  static const Color dError = Color(0xFFFF6B6B);
  static const Color dErrorBg = Color(0xFF3A1D22);
  static const Color dInfo = Color(0xFF60A5FA);

  // --- Mode clair ---
  static const Color lBg = Color(0xFFFAF9FC);
  static const Color lSurface1 = Color(0xFFFFFFFF);
  static const Color lSurface2 = Color(0xFFF2EFF9);
  static const Color lSurface3 = Color(0xFFE9E4F3);
  static const Color lPrimary = Color(0xFF6C3BD9);
  static const Color lContainer = Color(0xFFEADDFF);
  static const Color lOnContainer = Color(0xFF22005D);
  static const Color lAccent = Color(0xFF6C3BD9);
  static const Color lTextPrimary = Color(0xFF1A1622);
  static const Color lTextSecondary = Color(0xFF4A4458);
  static const Color lTextTertiary = Color(0xFF7C7589);
  static const Color lBorder = Color(0xFFE1DBEC);
  static const Color lSuccess = Color(0xFF15803D);
  static const Color lSuccessBg = Color(0xFFDCFCE7);
  static const Color lWarning = Color(0xFFB45309);
  static const Color lWarningBg = Color(0xFFFEF3C7);
  static const Color lError = Color(0xFFDC2626);
  static const Color lErrorBg = Color(0xFFFEE2E2);
  static const Color lInfo = Color(0xFF2563EB);
}

/// Couleurs sémantiques Vibeo non couvertes par le [ColorScheme] Material
/// (succès, attention, info + le dégradé signature), exposées comme
/// extension de thème pour rester correctes en clair ET en sombre.
@immutable
class VibeoColors extends ThemeExtension<VibeoColors> {
  const VibeoColors({
    required this.success,
    required this.onSuccessContainer,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.info,
    required this.gradient,
  });

  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color warningContainer;
  final Color info;
  final LinearGradient gradient;

  static const VibeoColors dark = VibeoColors(
    success: AppColors.dSuccess,
    successContainer: AppColors.dSuccessBg,
    onSuccessContainer: AppColors.dSuccess,
    warning: AppColors.dWarning,
    warningContainer: AppColors.dWarningBg,
    info: AppColors.dInfo,
    gradient: AppColors.signatureGradient,
  );

  static const VibeoColors light = VibeoColors(
    success: AppColors.lSuccess,
    successContainer: AppColors.lSuccessBg,
    onSuccessContainer: AppColors.lSuccess,
    warning: AppColors.lWarning,
    warningContainer: AppColors.lWarningBg,
    info: AppColors.lInfo,
    gradient: AppColors.signatureGradient,
  );

  /// Raccourci : `Theme.of(context).extension<VibeoColors>()!`.
  static VibeoColors of(BuildContext context) =>
      Theme.of(context).extension<VibeoColors>()!;

  @override
  VibeoColors copyWith({
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? warningContainer,
    Color? info,
    LinearGradient? gradient,
  }) {
    return VibeoColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      info: info ?? this.info,
      gradient: gradient ?? this.gradient,
    );
  }

  @override
  VibeoColors lerp(ThemeExtension<VibeoColors>? other, double t) {
    if (other is! VibeoColors) return this;
    return VibeoColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      info: Color.lerp(info, other.info, t)!,
      gradient: LinearGradient.lerp(gradient, other.gradient, t)!,
    );
  }
}
