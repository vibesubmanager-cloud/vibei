import 'package:flutter/material.dart';

/// VIVEI design tokens (dark-first; light + high-contrast variants in theme).
abstract final class VeTokens {
  // Dark
  static const bgDark = Color(0xFF0B1020);
  static const surfaceDark = Color(0xFF141B34);
  static const surfaceElevatedDark = Color(0xFF1C2547);
  static const textPrimaryDark = Color(0xFFF5F7FF);
  static const textSecondaryDark = Color(0xFFB8C0E0);

  // Light (warm white / deep ink)
  static const bgLight = Color(0xFFF7F5F1);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceElevatedLight = Color(0xFFEEEAE3);
  static const textPrimaryLight = Color(0xFF0B1020);
  static const textSecondaryLight = Color(0xFF3A4260);

  // High contrast
  static const bgHc = Color(0xFF000000);
  static const surfaceHc = Color(0xFF000000);
  static const textPrimaryHc = Color(0xFFFFFFFF);
  static const textSecondaryHc = Color(0xFFFFFFFF);
  static const accentHc = Color(0xFFFFE600);
  static const focusHc = Color(0xFFFFE600);

  // Shared accents (verified for ≥4.5:1 on dark surfaces for large type)
  static const accentStart = Color(0xFF7C5CFF);
  static const accentEnd = Color(0xFF22D3EE);
  static const focusRing = Color(0xFFFFD166);
  static const success = Color(0xFF34D399);
  static const danger = Color(0xFFFF6B6B);

  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentStart, accentEnd],
  );

  // Type scale (sp) — Atkinson Hyperlegible
  static const display = 40.0;
  static const title = 32.0;
  static const heading = 24.0;
  static const body = 18.0;
  static const label = 16.0;

  // Spacing / shape
  static const space = 8.0;
  static const radiusCard = 28.0;
  static const radiusPill = 999.0;
  static const targetPrimary = 64.0;
  static const targetSecondary = 56.0;

  // Motion
  static const durFast = Duration(milliseconds: 200);
  static const durMed = Duration(milliseconds: 320);
  static const durHero = Duration(milliseconds: 350);
  static const curveIn = Curves.easeOutCubic;
  static const curveIo = Curves.easeInOut;

  static const fontFamily = 'AtkinsonHyperlegible';
}
