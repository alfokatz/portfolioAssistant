import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show Provider;
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

ColorScheme _buildColorScheme(Brightness brightness) {
  if (brightness == Brightness.dark) {
    // Mismo mapeo de roles que el claro, con `PortfolioColorsDark`: así los
    // widgets de Material (switches, progress, snackbars, date pickers)
    // hablan el mismo idioma tibio que el resto, en vez de un gris neutro
    // aparte.
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: PortfolioColorsDark.accent,
      onPrimary: PortfolioColorsDark.onAccent,
      primaryContainer: Color(0xFF3C3129), // accent @ 16% sobre card
      onPrimaryContainer: PortfolioColorsDark.accent,
      secondary: PortfolioColorsDark.benchmarkSp500,
      onSecondary: PortfolioColorsDark.background,
      secondaryContainer: PortfolioColorsDark.surfaceElevated,
      onSecondaryContainer: PortfolioColorsDark.textSecondary,
      error: PortfolioColorsDark.loss,
      onError: PortfolioColorsDark.background,
      errorContainer: PortfolioColorsDark.lossContainer,
      onErrorContainer: PortfolioColorsDark.loss,
      surface: PortfolioColorsDark.background,
      onSurface: PortfolioColorsDark.textPrimary,
      onSurfaceVariant: PortfolioColorsDark.textSecondary,
      outline: PortfolioColorsDark.border,
      outlineVariant: PortfolioColorsDark.chartGrid,
      tertiary: PortfolioColorsDark.profit,
      onTertiary: PortfolioColorsDark.background,
      tertiaryContainer: PortfolioColorsDark.profitContainer,
      onTertiaryContainer: PortfolioColorsDark.profit,
      shadow: Color(0x66000000),
      inverseSurface: PortfolioColorsDark.textPrimary,
      onInverseSurface: PortfolioColorsDark.background,
      inversePrimary: PortfolioColorsDark.accentDim,
      surfaceTint: Colors.transparent,
      surfaceContainerHighest: PortfolioColorsDark.surfaceElevated,
      surfaceContainerHigh: PortfolioColorsDark.surfaceCard,
      surfaceContainer: PortfolioColorsDark.surfaceCard,
      surfaceContainerLow: PortfolioColorsDark.background,
      surfaceContainerLowest: PortfolioColorsDark.background,
    );
  }

  return const ColorScheme(
    brightness: Brightness.light,
    primary: PortfolioColors.accentBlue,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFFBE8DA),
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
