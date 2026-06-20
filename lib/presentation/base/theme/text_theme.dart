import 'package:flutter/material.dart';
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

TextStyle _style(
  TextStyle? base, {
  required FontWeight fontWeight,
  required double fontSize,
  double letterSpacing = 0,
  required double height,
  List<FontFeature>? fontFeatures,
}) {
  return base!.copyWith(
    fontWeight: fontWeight,
    fontSize: fontSize,
    letterSpacing: letterSpacing,
    height: height,
    fontFeatures: fontFeatures,
  );
}

final textThemeProvider = Provider<TextTheme>((ref) {
  final base = Typography.material2021().black;

  return base.copyWith(
    displayLarge: _style(
      base.displayLarge,
      fontWeight: FontWeights.bold,
      fontSize: 44,
      letterSpacing: -1.5,
      height: 1.0,
      fontFeatures: _tabular,
    ),
    displayMedium: _style(
      base.displayMedium,
      fontWeight: FontWeights.bold,
      fontSize: 34,
      letterSpacing: -1.0,
      height: 1.05,
      fontFeatures: _tabular,
    ),
    displaySmall: _style(
      base.displaySmall,
      fontWeight: FontWeights.semiBold,
      fontSize: 26,
      letterSpacing: -0.5,
      height: 1.1,
      fontFeatures: _tabular,
    ),
    headlineLarge: _style(
      base.headlineLarge,
      fontWeight: FontWeights.semiBold,
      fontSize: 20,
      letterSpacing: -0.3,
      height: 1.2,
    ),
    headlineMedium: _style(
      base.headlineMedium,
      fontWeight: FontWeights.semiBold,
      fontSize: 17,
      letterSpacing: -0.2,
      height: 1.25,
    ),
    headlineSmall: _style(
      base.headlineSmall,
      fontWeight: FontWeights.semiBold,
      fontSize: 15,
      letterSpacing: -0.1,
      height: 1.3,
    ),
    titleLarge: _style(
      base.titleLarge,
      fontWeight: FontWeights.semiBold,
      fontSize: 20,
      letterSpacing: -0.2,
      height: 1.2,
    ),
    titleMedium: _style(
      base.titleMedium,
      fontWeight: FontWeights.medium,
      fontSize: 16,
      letterSpacing: -0.1,
      height: 1.3,
    ),
    titleSmall: _style(
      base.titleSmall,
      fontWeight: FontWeights.semiBold,
      fontSize: 14,
      height: 1.3,
    ),
    bodyLarge: _style(
      base.bodyLarge,
      fontWeight: FontWeights.regular,
      fontSize: 16,
      height: 1.55,
    ),
    bodyMedium: _style(
      base.bodyMedium,
      fontWeight: FontWeights.regular,
      fontSize: 14,
      height: 1.5,
    ),
    bodySmall: _style(
      base.bodySmall,
      fontWeight: FontWeights.regular,
      fontSize: 12,
      height: 1.45,
    ),
    labelLarge: _style(
      base.labelLarge,
      fontWeight: FontWeights.medium,
      fontSize: 13,
      letterSpacing: 0.1,
      height: 1.3,
    ),
    labelMedium: _style(
      base.labelMedium,
      fontWeight: FontWeights.medium,
      fontSize: 11,
      letterSpacing: 0.2,
      height: 1.3,
    ),
    labelSmall: _style(
      base.labelSmall,
      fontWeight: FontWeights.medium,
      fontSize: 10,
      letterSpacing: 0.4,
      height: 1.3,
    ),
  );
});
