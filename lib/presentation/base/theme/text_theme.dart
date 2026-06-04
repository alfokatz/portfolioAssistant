// lib/src/theme/typography_provider.dart

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show Provider;

/// 1️⃣ Font family providers (swap por tus propias fuentes)
final titleFontFamilyProvider = Provider<String>((_) => 'FontFamilyTitle');
final bodyFontFamilyProvider = Provider<String>((_) => 'Figtree');

/// 2️⃣ Escalas tipográficas
class FontWeights {
  static const extraBold = FontWeight.w800;
  static const bold = FontWeight.w700;
  static const semiBold = FontWeight.w600;
  static const medium = FontWeight.w500;
  static const regular = FontWeight.w400;
}

class FontSizes {
  static const xxs = 12.0;
  static const xs = 14.0;
  static const sm = 16.0;
  static const md = 18.0;
  static const lg = 20.0;
  static const xl = 22.0;
  static const x2l = 24.0;
  static const x3l = 32.0;
}

class LineHeights {
  static const xxs = 16.0;
  static const xs = 18.0;
  static const sm = 20.0;
  static const md = 22.0;
  static const lg = 26.0;
  static const xl = 30.0;
  static const x2l = 32.0;
  static const x3l = 40.0;
}

/// 3️⃣ TextTheme Provider (Material 3 + tu escala tipográfica)
final textThemeProvider = Provider<TextTheme>((ref) {
  final titleFont = ref.watch(titleFontFamilyProvider);
  final bodyFont = ref.watch(bodyFontFamilyProvider);
  // Dark-first app: use the white typographic baseline so default text
  // (including input text) renders correctly on dark surfaces.
  final base = Typography.material2021().white;

  return base.copyWith(
    // Display (títulos grandes)
    displayLarge: base.displayLarge?.copyWith(
      fontFamily: titleFont,
      fontWeight: FontWeights.semiBold,
      fontSize: FontSizes.x3l,
      height: LineHeights.x3l / FontSizes.x3l,
    ),

    displayMedium: base.displayMedium?.copyWith(
      fontFamily: titleFont,
      fontWeight: FontWeights.semiBold,
      fontSize: FontSizes.x2l,
      height: LineHeights.x2l / FontSizes.x2l,
    ),

    displaySmall: base.displaySmall?.copyWith(
      fontFamily: titleFont,
      fontWeight: FontWeights.semiBold,
      fontSize: FontSizes.xl,
      height: LineHeights.xl / FontSizes.xl,
    ),

    // Headline (encabezados)
    headlineLarge: base.headlineLarge?.copyWith(
      fontFamily: titleFont,
      fontWeight: FontWeights.medium,
      fontSize: FontSizes.lg,
      height: LineHeights.lg / FontSizes.lg,
    ),
    headlineMedium: base.headlineMedium?.copyWith(
      fontFamily: titleFont,
      fontWeight: FontWeights.medium,
      fontSize: FontSizes.md,
      height: LineHeights.md / FontSizes.md,
    ),
    headlineSmall: base.headlineSmall?.copyWith(
      fontFamily: titleFont,
      fontWeight: FontWeights.medium,
      fontSize: FontSizes.sm,
      height: LineHeights.sm / FontSizes.sm,
    ),

    // Body (texto de párrafo)
    bodyLarge: base.bodyLarge?.copyWith(
      fontFamily: bodyFont,
      fontWeight: FontWeights.regular,
      fontSize: FontSizes.sm,
      height: LineHeights.sm / FontSizes.sm,
    ),
    bodyMedium: base.bodyMedium?.copyWith(
      fontFamily: bodyFont,
      fontWeight: FontWeights.regular,
      fontSize: FontSizes.xs,
      height: LineHeights.xs / FontSizes.xs,
    ),
    bodySmall: base.bodySmall?.copyWith(
      fontFamily: bodyFont,
      fontWeight: FontWeights.regular,
      fontSize: FontSizes.xxs,
      height: LineHeights.xxs / FontSizes.xxs,
    ),

    // Label (botones y anotaciones)
    labelLarge: base.labelLarge?.copyWith(
      fontFamily: bodyFont,
      fontWeight: FontWeights.medium,
      fontSize: FontSizes.xs,
      height: LineHeights.xs / FontSizes.xs,
    ),
    labelMedium: base.labelMedium?.copyWith(
      fontFamily: bodyFont,
      fontWeight: FontWeights.medium,
      fontSize: FontSizes.xxs,
      height: LineHeights.xxs / FontSizes.xxs,
    ),
    labelSmall: base.labelSmall?.copyWith(
      fontFamily: bodyFont,
      fontWeight: FontWeights.medium,
      fontSize: FontSizes.xxs,
      height: LineHeights.xxs / FontSizes.xxs,
    ),
  );
});
