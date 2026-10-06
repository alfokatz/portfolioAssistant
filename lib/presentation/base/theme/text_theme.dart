import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show Provider;

// Tabular figures para todos los números financieros
const _tabular = [FontFeature.tabularFigures()];

/// La familia empaquetada en `pubspec.yaml`, con sus cuatro pesos (400,
/// 500, 600, 700). No se usan las familias de google_fonts: registran una
/// familia por peso ("PlusJakartaSans_regular"), y un estilo que hereda la
/// regular y pide w700 no encontraba el archivo Bold (salía regular o con
/// negrita sintética, bug 2026-10-06).
const appFontFamily = 'Plus Jakarta Sans';

/// Un estilo de la familia de la app sobre [textStyle].
TextStyle jakarta({
  TextStyle? textStyle,
  FontWeight? fontWeight,
  double? fontSize,
  double? letterSpacing,
  double? height,
  List<FontFeature>? fontFeatures,
  TextDecoration? decoration,
  Color? color,
}) => (textStyle ?? const TextStyle()).copyWith(
  fontFamily: appFontFamily,
  fontWeight: fontWeight,
  fontSize: fontSize,
  letterSpacing: letterSpacing,
  height: height,
  fontFeatures: fontFeatures,
  decoration: decoration,
  color: color,
);

class FontWeights {
  static const extraBold = FontWeight.w800;
  static const bold = FontWeight.w700;
  static const semiBold = FontWeight.w600;
  static const medium = FontWeight.w500;
  static const regular = FontWeight.w400;
}

final textThemeProvider = Provider<TextTheme>((ref) {
  final base = Typography.material2021().black;
  final j = base.apply(fontFamily: appFontFamily);

  return j.copyWith(
    displayLarge: jakarta(
      textStyle: j.displayLarge,
      fontWeight: FontWeights.bold,
      fontSize: 44,
      letterSpacing: -1.5,
      height: 1.0,
      fontFeatures: _tabular,
    ),
    displayMedium: jakarta(
      textStyle: j.displayMedium,
      fontWeight: FontWeights.bold,
      fontSize: 34,
      letterSpacing: -1.0,
      height: 1.05,
      fontFeatures: _tabular,
    ),
    displaySmall: jakarta(
      textStyle: j.displaySmall,
      fontWeight: FontWeights.semiBold,
      fontSize: 26,
      letterSpacing: -0.5,
      height: 1.1,
      fontFeatures: _tabular,
    ),
    headlineLarge: jakarta(
      textStyle: j.headlineLarge,
      fontWeight: FontWeights.semiBold,
      fontSize: 20,
      letterSpacing: -0.3,
      height: 1.2,
    ),
    headlineMedium: jakarta(
      textStyle: j.headlineMedium,
      fontWeight: FontWeights.semiBold,
      fontSize: 17,
      letterSpacing: -0.2,
      height: 1.25,
    ),
    headlineSmall: jakarta(
      textStyle: j.headlineSmall,
      fontWeight: FontWeights.semiBold,
      fontSize: 15,
      letterSpacing: -0.1,
      height: 1.3,
    ),
    titleLarge: jakarta(
      textStyle: j.titleLarge,
      fontWeight: FontWeights.semiBold,
      fontSize: 20,
      letterSpacing: -0.2,
      height: 1.2,
    ),
    titleMedium: jakarta(
      textStyle: j.titleMedium,
      fontWeight: FontWeights.medium,
      fontSize: 16,
      letterSpacing: -0.1,
      height: 1.3,
    ),
    titleSmall: jakarta(
      textStyle: j.titleSmall,
      fontWeight: FontWeights.semiBold,
      fontSize: 14,
      height: 1.3,
    ),
    bodyLarge: jakarta(
      textStyle: j.bodyLarge,
      fontWeight: FontWeights.regular,
      fontSize: 16,
      height: 1.55,
    ),
    bodyMedium: jakarta(
      textStyle: j.bodyMedium,
      fontWeight: FontWeights.regular,
      fontSize: 14,
      height: 1.5,
    ),
    bodySmall: jakarta(
      textStyle: j.bodySmall,
      fontWeight: FontWeights.regular,
      fontSize: 12,
      height: 1.45,
    ),
    labelLarge: jakarta(
      textStyle: j.labelLarge,
      fontWeight: FontWeights.medium,
      fontSize: 13,
      letterSpacing: 0.1,
      height: 1.3,
    ),
    labelMedium: jakarta(
      textStyle: j.labelMedium,
      fontWeight: FontWeights.medium,
      fontSize: 11,
      letterSpacing: 0.2,
      height: 1.3,
    ),
    labelSmall: jakarta(
      textStyle: j.labelSmall,
      fontWeight: FontWeights.medium,
      fontSize: 10,
      letterSpacing: 0.4,
      height: 1.3,
    ),
  );
});
