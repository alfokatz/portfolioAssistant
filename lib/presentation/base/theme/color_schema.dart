import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show Provider;
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

ColorScheme _buildColorScheme(Brightness brightness) {
  if (brightness == Brightness.dark) {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF5BA3D0),
      onPrimary: Color(0xFF0F0F0F),
      primaryContainer: Color(0xFF1A3A4A),
      onPrimaryContainer: Color(0xFF5BA3D0),
      secondary: Color(0xFF6E6E72),
      onSecondary: Color(0xFFEDEDF0),
      secondaryContainer: Color(0xFF242424),
      onSecondaryContainer: Color(0xFF8A8A8E),
      error: Color(0xFFE57373),
      onError: Color(0xFF0F0F0F),
      errorContainer: Color(0xFF2E1A1A),
      onErrorContainer: Color(0xFFE57373),
      surface: Color(0xFF0F0F0F),
      onSurface: Color(0xFFEDEDF0),
      onSurfaceVariant: Color(0xFF8A8A8E),
      outline: Color(0x14FFFFFF),
      outlineVariant: Color(0x0FFFFFFF),
      tertiary: Color(0xFF5CB85C),
      onTertiary: Color(0xFF0F0F0F),
      tertiaryContainer: Color(0xFF1A2E1C),
      onTertiaryContainer: Color(0xFF5CB85C),
      shadow: Color(0x40000000),
      inverseSurface: Color(0xFFEDEDF0),
      onInverseSurface: Color(0xFF0F0F0F),
      inversePrimary: Color(0xFF1F6C9F),
      surfaceContainerHighest: Color(0xFF242424),
      surfaceContainerHigh: Color(0xFF1A1A1A),
      surfaceContainer: Color(0xFF1A1A1A),
      surfaceContainerLow: Color(0xFF0F0F0F),
      surfaceContainerLowest: Color(0xFF0F0F0F),
    );
  }

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
}

final colorSchemeLightProvider = Provider<ColorScheme>(
  (ref) => _buildColorScheme(Brightness.light),
);

final colorSchemeDarkProvider = Provider<ColorScheme>(
  (ref) => _buildColorScheme(Brightness.dark),
);

/// Backward compatibility alias.
final colorSchemeProvider = colorSchemeLightProvider;
