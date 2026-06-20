import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show Provider;
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

final colorSchemeProvider = Provider<ColorScheme>((ref) {
  return const ColorScheme(
    brightness: Brightness.light,
    primary: PortfolioColors.accentBlue,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFDCEEF8),
    onPrimaryContainer: PortfolioColors.accentBlueDim,
    secondary: PortfolioColors.benchmarkSp500,
    onSecondary: Colors.white,
    secondaryContainer: PortfolioColors.surfaceElevated,
    onSecondaryContainer: PortfolioColors.textSecondary,
    error: PortfolioColors.loss,
    onError: Colors.white,
    errorContainer: Color(0xFFFFEDED),
    onErrorContainer: PortfolioColors.loss,
    surface: PortfolioColors.background,
    onSurface: PortfolioColors.textPrimary,
    onSurfaceVariant: PortfolioColors.textSecondary,
    outline: PortfolioColors.border,
    outlineVariant: PortfolioColors.chartGrid,
    tertiary: PortfolioColors.profit,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFE8F5EA),
    onTertiaryContainer: PortfolioColors.profit,
    shadow: Color(0x14000000),
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
