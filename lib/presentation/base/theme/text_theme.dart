import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show Provider;

// Tabular figures para todos los números financieros
const _tabular = [FontFeature.tabularFigures()];

class FontWeights {
  static const extraBold = FontWeight.w800;
  static const bold = FontWeight.w700;
  static const semiBold = FontWeight.w600;
  static const medium = FontWeight.w500;
  static const regular = FontWeight.w400;
}

final textThemeProvider = Provider<TextTheme>((ref) {
  // Base oscuro — texto blanco por defecto para superficies dark
  final base = Typography.material2021().white;
  // Aplicar Plus Jakarta Sans a todo el sistema tipográfico
  final j = GoogleFonts.plusJakartaSansTextTheme(base);

  return j.copyWith(
    // ── Display ─────────────────────────────────────────────────────────
    // displayLarge: valor del portfolio (44px hero)
    displayLarge: GoogleFonts.plusJakartaSans(
      textStyle: j.displayLarge,
      fontWeight: FontWeights.bold,
      fontSize: 44,
      letterSpacing: -1.5,
      height: 1.0,
      fontFeatures: _tabular,
    ),
    displayMedium: GoogleFonts.plusJakartaSans(
      textStyle: j.displayMedium,
      fontWeight: FontWeights.bold,
      fontSize: 34,
      letterSpacing: -1.0,
      height: 1.05,
      fontFeatures: _tabular,
    ),
    displaySmall: GoogleFonts.plusJakartaSans(
      textStyle: j.displaySmall,
      fontWeight: FontWeights.semiBold,
      fontSize: 26,
      letterSpacing: -0.5,
      height: 1.1,
      fontFeatures: _tabular,
    ),

    // ── Headlines (sección headers) ────────────────────────────────────
    headlineLarge: GoogleFonts.plusJakartaSans(
      textStyle: j.headlineLarge,
      fontWeight: FontWeights.semiBold,
      fontSize: 20,
      letterSpacing: -0.3,
      height: 1.2,
    ),
    headlineMedium: GoogleFonts.plusJakartaSans(
      textStyle: j.headlineMedium,
      fontWeight: FontWeights.semiBold,
      fontSize: 17,
      letterSpacing: -0.2,
      height: 1.25,
    ),
    headlineSmall: GoogleFonts.plusJakartaSans(
      textStyle: j.headlineSmall,
      fontWeight: FontWeights.semiBold,
      fontSize: 15,
      letterSpacing: -0.1,
      height: 1.3,
    ),

    // ── Títulos (app bar, card titles) ────────────────────────────────
    titleLarge: GoogleFonts.plusJakartaSans(
      textStyle: j.titleLarge,
      fontWeight: FontWeights.semiBold,
      fontSize: 20,
      letterSpacing: -0.2,
      height: 1.2,
    ),
    titleMedium: GoogleFonts.plusJakartaSans(
      textStyle: j.titleMedium,
      fontWeight: FontWeights.medium,
      fontSize: 16,
      letterSpacing: -0.1,
      height: 1.3,
    ),
    titleSmall: GoogleFonts.plusJakartaSans(
      textStyle: j.titleSmall,
      fontWeight: FontWeights.semiBold,
      fontSize: 14,
      letterSpacing: 0,
      height: 1.3,
    ),

    // ── Body (párrafos, subtítulos) ───────────────────────────────────
    bodyLarge: GoogleFonts.plusJakartaSans(
      textStyle: j.bodyLarge,
      fontWeight: FontWeights.regular,
      fontSize: 16,
      letterSpacing: 0,
      height: 1.55,
    ),
    bodyMedium: GoogleFonts.plusJakartaSans(
      textStyle: j.bodyMedium,
      fontWeight: FontWeights.regular,
      fontSize: 14,
      letterSpacing: 0,
      height: 1.5,
    ),
    bodySmall: GoogleFonts.plusJakartaSans(
      textStyle: j.bodySmall,
      fontWeight: FontWeights.regular,
      fontSize: 12,
      letterSpacing: 0,
      height: 1.45,
    ),

    // ── Labels (badges, anotaciones, botones) ─────────────────────────
    labelLarge: GoogleFonts.plusJakartaSans(
      textStyle: j.labelLarge,
      fontWeight: FontWeights.medium,
      fontSize: 13,
      letterSpacing: 0.1,
      height: 1.3,
    ),
    labelMedium: GoogleFonts.plusJakartaSans(
      textStyle: j.labelMedium,
      fontWeight: FontWeights.medium,
      fontSize: 11,
      letterSpacing: 0.2,
      height: 1.3,
    ),
    labelSmall: GoogleFonts.plusJakartaSans(
      textStyle: j.labelSmall,
      fontWeight: FontWeights.medium,
      fontSize: 10,
      letterSpacing: 0.4,
      height: 1.3,
    ),
  );
});
