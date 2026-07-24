import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Construit les thèmes clair et sombre de Vibeo à partir des jetons du design
/// system. Police unique : Plus Jakarta Sans. Formes : champs/cartes 12 px,
/// boutons en pilule.
class AppTheme {
  const AppTheme._();

  static const double _radiusCard = 12;
  static const double _radiusSheet = 20;

  /// Thème sombre (thème par défaut de Vibeo).
  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    scheme: _darkScheme,
    vibeo: VibeoColors.dark,
    scaffoldBackground: AppColors.dBg,
  );

  /// Thème clair.
  static ThemeData get light => _build(
    brightness: Brightness.light,
    scheme: _lightScheme,
    vibeo: VibeoColors.light,
    scaffoldBackground: AppColors.lBg,
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.dPrimary,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: AppColors.dContainer,
    onPrimaryContainer: AppColors.dOnContainer,
    secondary: AppColors.dPrimaryVariant,
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: AppColors.dContainer,
    onSecondaryContainer: AppColors.dOnContainer,
    tertiary: AppColors.dAccent,
    onTertiary: Color(0xFF1A1622),
    error: AppColors.dError,
    onError: Color(0xFF3A1D22),
    errorContainer: AppColors.dErrorBg,
    onErrorContainer: Color(0xFFFFDAD6),
    surface: AppColors.dBg,
    onSurface: AppColors.dTextPrimary,
    surfaceContainerLowest: AppColors.dBg,
    surfaceContainerLow: AppColors.dSurface1,
    surfaceContainer: AppColors.dSurface1,
    surfaceContainerHigh: AppColors.dSurface2,
    surfaceContainerHighest: AppColors.dSurface3,
    onSurfaceVariant: AppColors.dTextSecondary,
    outline: AppColors.dBorder,
    outlineVariant: AppColors.dBorder,
    tertiaryContainer: AppColors.dContainer,
    onTertiaryContainer: AppColors.dOnContainer,
    inverseSurface: AppColors.dTextPrimary,
    onInverseSurface: AppColors.dBg,
    inversePrimary: AppColors.lPrimary,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.lPrimary,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: AppColors.lContainer,
    onPrimaryContainer: AppColors.lOnContainer,
    secondary: AppColors.lPrimary,
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: AppColors.lContainer,
    onSecondaryContainer: AppColors.lOnContainer,
    tertiary: AppColors.lAccent,
    onTertiary: Color(0xFFFFFFFF),
    error: AppColors.lError,
    onError: Color(0xFFFFFFFF),
    errorContainer: AppColors.lErrorBg,
    onErrorContainer: Color(0xFF410002),
    surface: AppColors.lBg,
    onSurface: AppColors.lTextPrimary,
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: AppColors.lSurface1,
    surfaceContainer: AppColors.lSurface2,
    surfaceContainerHigh: AppColors.lSurface3,
    surfaceContainerHighest: AppColors.lSurface3,
    onSurfaceVariant: AppColors.lTextSecondary,
    outline: AppColors.lBorder,
    outlineVariant: AppColors.lBorder,
    tertiaryContainer: AppColors.lContainer,
    onTertiaryContainer: AppColors.lOnContainer,
    inverseSurface: AppColors.lTextPrimary,
    onInverseSurface: AppColors.lBg,
    inversePrimary: AppColors.dPrimary,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required VibeoColors vibeo,
    required Color scaffoldBackground,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
    );

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(
      base.textTheme,
    ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    final pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
    );
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_radiusCard),
    );

    return base.copyWith(
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[vibeo],
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: cardShape,
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: pill,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: textTheme.labelLarge,
          minimumSize: const Size(0, 48),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: pill,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          minimumSize: const Size(0, 48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: pill,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: textTheme.labelLarge,
          minimumSize: const Size(0, 48),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: pill,
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusCard),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusCard),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusCard),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusCard),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusCard),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: pill,
        side: BorderSide(color: scheme.outline),
        backgroundColor: scheme.surfaceContainerHigh,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(_radiusSheet),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.all(textTheme.labelMedium),
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusCard),
        ),
      ),
    );
  }
}
