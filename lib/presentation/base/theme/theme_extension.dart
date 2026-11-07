import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

@immutable
class CustomColors extends ThemeExtension<CustomColors> {
  const CustomColors({
    required this.background,
    required this.surfaceCard,
    required this.surfaceElevated,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.profit,
    required this.loss,
    required this.profitContainer,
    required this.lossContainer,
    required this.chartGrid,
    required this.chartLine,
    required this.benchmarkSp500,
    required this.accentBlue,
    required this.accentWarm,
    required this.cardBackground,
    required this.aiCardBorder,
    required this.accentDim,
    required this.onAccent,
    required this.inset,
    required this.track,
    required this.chip,
    required this.onChip,
    required this.haloStrength,
    required this.glowScale,
  });

  final Color background;
  final Color surfaceCard;
  final Color surfaceElevated;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color profit;
  final Color loss;
  final Color profitContainer;
  final Color lossContainer;
  final Color chartGrid;
  final Color chartLine;
  final Color benchmarkSp500;
  final Color accentBlue;
  final Color accentWarm;
  final Color cardBackground;
  final Color aiCardBorder;

  /// Acento atenuado para links y acciones secundarias de texto.
  final Color accentDim;

  /// Texto e íconos sobre un relleno de acento (FAB, send, CTA terracota).
  final Color onAccent;

  /// Bloques internos de una card (más hundidos que la card).
  final Color inset;

  /// Fondo de barras de progreso y anillos.
  final Color track;

  /// Círculo de un ícono de fila (Ajustes, Metas, "Contale a Porty") y su
  /// ícono ([onChip]); [onChip] también es el color de una etiqueta
  /// neutra como "Recién empezás". En claro, terracota sobre su tinte; en
  /// oscuro, neutro sobre un escalón de grafito: diez círculos terracota
  /// por pantalla sobre el grafito se leían flúor (el acento queda para
  /// acciones: FAB, "Editar", switches).
  final Color chip;
  final Color onChip;

  /// Cuánto del acento tiñe el halo superior de `AppBackgroundGradient`
  /// (0–1). En oscuro es 0: cualquier lavado terracota sobre el grafito se
  /// veía como una mancha marrón.
  final double haloStrength;

  /// Multiplicador de la opacidad de glows (foco, send, mic). Sobre fondo
  /// oscuro un glow pleno se lee como neón; en oscuro baja a menos de la
  /// mitad.
  final double glowScale;

  Color pnlColor(double value) => value >= 0 ? profit : loss;

  static const light = CustomColors(
    background: PortfolioColors.background,
    surfaceCard: PortfolioColors.surfaceCard,
    surfaceElevated: PortfolioColors.surfaceElevated,
    border: PortfolioColors.border,
    textPrimary: PortfolioColors.textPrimary,
    textSecondary: PortfolioColors.textSecondary,
    profit: PortfolioColors.profit,
    loss: PortfolioColors.loss,
    profitContainer: Color(0xFFEDF3EC),
    lossContainer: Color(0xFFFDEBEC),
    chartGrid: PortfolioColors.chartGrid,
    chartLine: PortfolioColors.chartLine,
    benchmarkSp500: PortfolioColors.benchmarkSp500,
    accentBlue: PortfolioColors.accentBlue,
    accentWarm: PortfolioColors.accentWarm,
    cardBackground: PortfolioColors.surfaceCard,
    aiCardBorder: PortfolioColors.aiCardBorder,
    accentDim: PortfolioColors.accentBlueDim,
    onAccent: Colors.white,
    inset: Color(0xFFF7F6F3),
    track: Color(0x0F000000),
    chip: Color(0x1FD98E5D), // accentBlue @ 12%
    onChip: PortfolioColors.accentBlue,
    haloStrength: 0.32,
    glowScale: 1,
  );

  /// Ver `PortfolioColorsDark` para el porqué de cada valor.
  static const dark = CustomColors(
    background: PortfolioColorsDark.background,
    surfaceCard: PortfolioColorsDark.surfaceCard,
    surfaceElevated: PortfolioColorsDark.surfaceElevated,
    border: PortfolioColorsDark.border,
    textPrimary: PortfolioColorsDark.textPrimary,
    textSecondary: PortfolioColorsDark.textSecondary,
    profit: PortfolioColorsDark.profit,
    loss: PortfolioColorsDark.loss,
    profitContainer: PortfolioColorsDark.profitContainer,
    lossContainer: PortfolioColorsDark.lossContainer,
    chartGrid: PortfolioColorsDark.chartGrid,
    chartLine: PortfolioColorsDark.chartLine,
    benchmarkSp500: PortfolioColorsDark.benchmarkSp500,
    accentBlue: PortfolioColorsDark.accent, // mismo acento que accentWarm
    accentWarm: PortfolioColorsDark.accent,
    cardBackground: PortfolioColorsDark.surfaceCard,
    aiCardBorder: PortfolioColorsDark.aiCardBorder,
    accentDim: PortfolioColorsDark.accentDim,
    onAccent: PortfolioColorsDark.onAccent,
    inset: PortfolioColorsDark.inset,
    track: PortfolioColorsDark.track,
    chip: PortfolioColorsDark.surfaceElevated,
    onChip: PortfolioColorsDark.textSecondary,
    haloStrength: 0,
    glowScale: 0.35,
  );

  @override
  CustomColors copyWith({
    Color? background,
    Color? surfaceCard,
    Color? surfaceElevated,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? profit,
    Color? loss,
    Color? profitContainer,
    Color? lossContainer,
    Color? chartGrid,
    Color? chartLine,
    Color? benchmarkSp500,
    Color? accentBlue,
    Color? accentWarm,
    Color? cardBackground,
    Color? aiCardBorder,
    Color? accentDim,
    Color? onAccent,
    Color? inset,
    Color? track,
    Color? chip,
    Color? onChip,
    double? haloStrength,
    double? glowScale,
  }) {
    return CustomColors(
      background: background ?? this.background,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      profit: profit ?? this.profit,
      loss: loss ?? this.loss,
      profitContainer: profitContainer ?? this.profitContainer,
      lossContainer: lossContainer ?? this.lossContainer,
      chartGrid: chartGrid ?? this.chartGrid,
      chartLine: chartLine ?? this.chartLine,
      benchmarkSp500: benchmarkSp500 ?? this.benchmarkSp500,
      accentBlue: accentBlue ?? this.accentBlue,
      accentWarm: accentWarm ?? this.accentWarm,
      cardBackground: cardBackground ?? this.cardBackground,
      aiCardBorder: aiCardBorder ?? this.aiCardBorder,
      accentDim: accentDim ?? this.accentDim,
      onAccent: onAccent ?? this.onAccent,
      inset: inset ?? this.inset,
      track: track ?? this.track,
      chip: chip ?? this.chip,
      onChip: onChip ?? this.onChip,
      haloStrength: haloStrength ?? this.haloStrength,
      glowScale: glowScale ?? this.glowScale,
    );
  }

  @override
  CustomColors lerp(ThemeExtension<CustomColors>? other, double t) {
    if (other is! CustomColors) return this;
    return CustomColors(
      background: Color.lerp(background, other.background, t)!,
      surfaceCard: Color.lerp(surfaceCard, other.surfaceCard, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      profit: Color.lerp(profit, other.profit, t)!,
      loss: Color.lerp(loss, other.loss, t)!,
      profitContainer: Color.lerp(profitContainer, other.profitContainer, t)!,
      lossContainer: Color.lerp(lossContainer, other.lossContainer, t)!,
      chartGrid: Color.lerp(chartGrid, other.chartGrid, t)!,
      chartLine: Color.lerp(chartLine, other.chartLine, t)!,
      benchmarkSp500: Color.lerp(benchmarkSp500, other.benchmarkSp500, t)!,
      accentBlue: Color.lerp(accentBlue, other.accentBlue, t)!,
      accentWarm: Color.lerp(accentWarm, other.accentWarm, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      aiCardBorder: Color.lerp(aiCardBorder, other.aiCardBorder, t)!,
      accentDim: Color.lerp(accentDim, other.accentDim, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      inset: Color.lerp(inset, other.inset, t)!,
      track: Color.lerp(track, other.track, t)!,
      chip: Color.lerp(chip, other.chip, t)!,
      onChip: Color.lerp(onChip, other.onChip, t)!,
      haloStrength: lerpDouble(haloStrength, other.haloStrength, t)!,
      glowScale: lerpDouble(glowScale, other.glowScale, t)!,
    );
  }
}

extension CustomColorsX on BuildContext {
  CustomColors get customColors => Theme.of(this).extension<CustomColors>()!;
}
