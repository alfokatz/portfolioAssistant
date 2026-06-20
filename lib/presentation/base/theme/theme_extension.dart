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
    required this.cardBackground,
    required this.aiCardBorder,
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
  final Color cardBackground;
  final Color aiCardBorder;

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
    cardBackground: PortfolioColors.surfaceCard,
    aiCardBorder: PortfolioColors.border,
  );

  static const dark = CustomColors(
    background: Color(0xFF0F0F0F),
    surfaceCard: Color(0xFF1A1A1A),
    surfaceElevated: Color(0xFF242424),
    border: Color(0x14FFFFFF),
    textPrimary: Color(0xFFEDEDF0),
    textSecondary: Color(0xFF8A8A8E),
    profit: Color(0xFF5CB85C),
    loss: Color(0xFFE57373),
    profitContainer: Color(0xFF1A2E1C),
    lossContainer: Color(0xFF2E1A1A),
    chartGrid: Color(0x0FFFFFFF),
    chartLine: Color(0xFFEDEDF0),
    benchmarkSp500: Color(0xFF8A8582),
    accentBlue: Color(0xFF5BA3D0),
    cardBackground: Color(0xFF1A1A1A),
    aiCardBorder: Color(0x14FFFFFF),
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
    Color? cardBackground,
    Color? aiCardBorder,
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
      cardBackground: cardBackground ?? this.cardBackground,
      aiCardBorder: aiCardBorder ?? this.aiCardBorder,
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
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      aiCardBorder: Color.lerp(aiCardBorder, other.aiCardBorder, t)!,
    );
  }
}

extension CustomColorsX on BuildContext {
  CustomColors get customColors => Theme.of(this).extension<CustomColors>()!;
}
