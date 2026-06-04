import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show Provider;
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

final colorSchemeProvider = Provider<ColorScheme>((ref) {
  return const ColorScheme(
    brightness: Brightness.dark,
    primary: PortfolioColors.accentBlue,
    onPrimary: PortfolioColors.textPrimary,
    primaryContainer: PortfolioColors.accentBlueDim,
    onPrimaryContainer: PortfolioColors.textPrimary,
    secondary: PortfolioColors.benchmarkSp500,
    onSecondary: PortfolioColors.textPrimary,
    secondaryContainer: PortfolioColors.surfaceElevated,
    onSecondaryContainer: PortfolioColors.textSecondary,
    error: PortfolioColors.loss,
    onError: PortfolioColors.textPrimary,
    errorContainer: Color(0xFF3D1515),
    onErrorContainer: Color(0xFFFFCDD2),
    surface: PortfolioColors.background,
    onSurface: PortfolioColors.textPrimary,
    onSurfaceVariant: PortfolioColors.textSecondary,
    outline: PortfolioColors.border,
    outlineVariant: PortfolioColors.chartGrid,
    tertiary: PortfolioColors.profit,
    onTertiary: PortfolioColors.background,
    tertiaryContainer: Color(0xFF14532D),
    onTertiaryContainer: PortfolioColors.profit,
    shadow: Color(0xFF000000),
    inverseSurface: PortfolioColors.textPrimary,
    onInverseSurface: PortfolioColors.background,
    inversePrimary: PortfolioColors.accentBlueDim,
    surfaceContainerHighest: PortfolioColors.surfaceElevated,
    surfaceContainerHigh: PortfolioColors.surfaceCard,
    surfaceContainer: PortfolioColors.surfaceCard,
    surfaceContainerLow: PortfolioColors.background,
    surfaceContainerLowest: PortfolioColors.background,
  );
});
