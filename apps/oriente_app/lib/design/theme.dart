import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

enum VeThemeMode { system, dark, light, highContrast }

class OrienteTheme {
  /// Legacy entry — dark theme (kept for call sites).
  static ThemeData light() => dark();

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        bg: VeTokens.bgDark,
        surface: VeTokens.surfaceDark,
        elevated: VeTokens.surfaceElevatedDark,
        text: VeTokens.textPrimaryDark,
        textMuted: VeTokens.textSecondaryDark,
        accent: VeTokens.accentStart,
        onAccent: VeTokens.textPrimaryDark,
        focus: VeTokens.focusRing,
        highContrast: false,
      );

  static ThemeData lightTheme() => _build(
        brightness: Brightness.light,
        bg: VeTokens.bgLight,
        surface: VeTokens.surfaceLight,
        elevated: VeTokens.surfaceElevatedLight,
        text: VeTokens.textPrimaryLight,
        textMuted: VeTokens.textSecondaryLight,
        accent: VeTokens.accentStart,
        onAccent: Colors.white,
        focus: const Color(0xFF5B3FD6),
        highContrast: false,
      );

  static ThemeData highContrast() => _build(
        brightness: Brightness.dark,
        bg: VeTokens.bgHc,
        surface: VeTokens.surfaceHc,
        elevated: const Color(0xFF111111),
        text: VeTokens.textPrimaryHc,
        textMuted: VeTokens.textSecondaryHc,
        accent: VeTokens.accentHc,
        onAccent: Colors.black,
        focus: VeTokens.focusHc,
        highContrast: true,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color elevated,
    required Color text,
    required Color textMuted,
    required Color accent,
    required Color onAccent,
    required Color focus,
    required bool highContrast,
  }) {
    final base = TextTheme(
      displayLarge: TextStyle(
        fontFamily: VeTokens.fontFamily,
        fontSize: VeTokens.display,
        fontWeight: FontWeight.w700,
        color: text,
        height: 1.15,
        letterSpacing: 0.4,
      ),
      headlineMedium: TextStyle(
        fontFamily: VeTokens.fontFamily,
        fontSize: VeTokens.title,
        fontWeight: FontWeight.w700,
        color: text,
        height: 1.2,
      ),
      titleLarge: TextStyle(
        fontFamily: VeTokens.fontFamily,
        fontSize: VeTokens.heading,
        fontWeight: FontWeight.w700,
        color: text,
        height: 1.25,
      ),
      bodyLarge: TextStyle(
        fontFamily: VeTokens.fontFamily,
        fontSize: VeTokens.body,
        fontWeight: FontWeight.w400,
        color: text,
        height: 1.4,
      ),
      bodyMedium: TextStyle(
        fontFamily: VeTokens.fontFamily,
        fontSize: VeTokens.label,
        fontWeight: FontWeight.w400,
        color: textMuted,
        height: 1.35,
      ),
      labelLarge: TextStyle(
        fontFamily: VeTokens.fontFamily,
        fontSize: VeTokens.body,
        fontWeight: FontWeight.w700,
        color: onAccent,
        height: 1.2,
      ),
    );

    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      secondary: VeTokens.accentEnd,
      onSecondary: onAccent,
      error: VeTokens.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: scheme,
      textTheme: base,
      fontFamily: VeTokens.fontFamily,
      cardColor: elevated,
      dividerColor: textMuted.withValues(alpha: 0.25),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: base.titleLarge,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return accent;
          return textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return accent.withValues(alpha: 0.45);
          }
          return textMuted.withValues(alpha: 0.25);
        }),
        overlayColor: WidgetStateProperty.all(focus.withValues(alpha: 0.25)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(
            color: highContrast ? focus : textMuted.withValues(alpha: 0.55),
            width: highContrast ? 3 : 2,
          ),
          minimumSize: const Size(64, VeTokens.targetPrimary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VeTokens.radiusCard),
          ),
          textStyle: base.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          minimumSize: const Size(64, VeTokens.targetPrimary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VeTokens.radiusCard),
          ),
          textStyle: base.labelLarge,
        ),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 16,
        iconColor: text,
        textColor: text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      focusColor: focus.withValues(alpha: 0.35),
      highlightColor: focus.withValues(alpha: 0.12),
    );
  }
}
