import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Semantic design tokens for the Clean Premium Dental palette in Light & Dark modes.
class DentalThemeTokens extends ThemeExtension<DentalThemeTokens> {
  const DentalThemeTokens({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceMuted,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.teal,
    required this.tealDark,
    required this.tealSoft,
    required this.blue,
    required this.blueSoft,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.error,
    required this.errorSoft,
  });

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceMuted;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color teal;
  final Color tealDark;
  final Color tealSoft;
  final Color blue;
  final Color blueSoft;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color error;
  final Color errorSoft;

  static const DentalThemeTokens light = DentalThemeTokens(
    background: Color(0xFFF5FAFB),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFEDF6F8),
    surfaceMuted: Color(0xFFF0F7F9),
    border: Color(0xFFDCE9EE),
    textPrimary: Color(0xFF14283F),
    textSecondary: Color(0xFF64748B),
    textMuted: Color(0xFF94A3B8),
    teal: Color(0xFF0D9488),
    tealDark: Color(0xFF0F766E),
    tealSoft: Color(0xFFDDF7F0),
    blue: Color(0xFF0284C7),
    blueSoft: Color(0xFFE0F2FE),
    success: Color(0xFF16A34A),
    successSoft: Color(0xFFDCFCE7),
    warning: Color(0xFFD97706),
    warningSoft: Color(0xFFFEF3C7),
    error: Color(0xFFDC2626),
    errorSoft: Color(0xFFFEE2E2),
  );

  static const DentalThemeTokens dark = DentalThemeTokens(
    background: Color(0xFF0B1728),
    surface: Color(0xFF12243A),
    surfaceElevated: Color(0xFF1A3047),
    surfaceMuted: Color(0xFF162B44),
    border: Color(0xFF253F5B),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFFA5B4C7),
    textMuted: Color(0xFF7B8FA6),
    teal: Color(0xFF2DD4BF),
    tealDark: Color(0xFF14B8A6),
    tealSoft: Color(0xFF133A3E),
    blue: Color(0xFF38BDF8),
    blueSoft: Color(0xFF13324D),
    success: Color(0xFF4ADE80),
    successSoft: Color(0xFF123626),
    warning: Color(0xFFFBBF24),
    warningSoft: Color(0xFF3B2B12),
    error: Color(0xFFF87171),
    errorSoft: Color(0xFF3F1A22),
  );

  @override
  DentalThemeTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceMuted,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? teal,
    Color? tealDark,
    Color? tealSoft,
    Color? blue,
    Color? blueSoft,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? error,
    Color? errorSoft,
  }) {
    return DentalThemeTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      teal: teal ?? this.teal,
      tealDark: tealDark ?? this.tealDark,
      tealSoft: tealSoft ?? this.tealSoft,
      blue: blue ?? this.blue,
      blueSoft: blueSoft ?? this.blueSoft,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      error: error ?? this.error,
      errorSoft: errorSoft ?? this.errorSoft,
    );
  }

  @override
  DentalThemeTokens lerp(ThemeExtension<DentalThemeTokens>? other, double t) {
    if (other is! DentalThemeTokens) return this;
    return DentalThemeTokens(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      teal: Color.lerp(teal, other.teal, t)!,
      tealDark: Color.lerp(tealDark, other.tealDark, t)!,
      tealSoft: Color.lerp(tealSoft, other.tealSoft, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      blueSoft: Color.lerp(blueSoft, other.blueSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorSoft: Color.lerp(errorSoft, other.errorSoft, t)!,
    );
  }
}

extension DentalThemeBuildContext on BuildContext {
  DentalThemeTokens get dentalColors =>
      Theme.of(this).extension<DentalThemeTokens>() ?? DentalThemeTokens.light;
}

/// Central theme definitions for the Dental Queue patient mobile application.
class AppTheme {
  AppTheme._();

  // Option 1 Clean Premium Dental static references
  static const Color primary = Color(0xFF0D9488); // Teal Care
  static const Color primaryDark = Color(0xFF0F766E);
  static const Color primaryLight = Color(0xFFDDF7F0); // Soft Mint
  static const Color secondary = Color(0xFF0284C7); // Trust Blue
  static const Color accent = Color(0xFF2DD4BF);

  static const Color background = Color(0xFFF5FAFB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color cardBorder = Color(0xFFDCE9EE);
  static const Color textPrimary = Color(0xFF14283F);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);

  // Status colors
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color error = Color(0xFFDC2626);

  static final ThemeData lightTheme = _buildTheme(
    brightness: Brightness.light,
    tokens: DentalThemeTokens.light,
  );

  static final ThemeData darkTheme = _buildTheme(
    brightness: Brightness.dark,
    tokens: DentalThemeTokens.dark,
  );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required DentalThemeTokens tokens,
  }) {
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      extensions: [tokens],
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: tokens.teal,
        onPrimary: isDark ? const Color(0xFF042F2E) : Colors.white,
        secondary: tokens.blue,
        onSecondary: isDark ? const Color(0xFF082F49) : Colors.white,
        error: tokens.error,
        onError: Colors.white,
        surface: tokens.surface,
        onSurface: tokens.textPrimary,
      ),
      scaffoldBackgroundColor: tokens.background,
      dividerColor: tokens.border,
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.surface,
        foregroundColor: tokens.textPrimary,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: tokens.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        iconTheme: IconThemeData(color: tokens.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: tokens.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surfaceMuted,
        labelStyle: TextStyle(color: tokens.textSecondary),
        hintStyle: TextStyle(color: tokens.textMuted),
        prefixIconColor: tokens.textSecondary,
        suffixIconColor: tokens.textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.teal, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.error, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? const Color(0xFF0D9488) : tokens.teal,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.teal,
          side: BorderSide(color: tokens.teal, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: tokens.border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: tokens.tealSoft,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tokens.teal,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: tokens.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: tokens.teal, size: 24);
          }
          return IconThemeData(color: tokens.textSecondary, size: 24);
        }),
      ),
    );
  }
}
