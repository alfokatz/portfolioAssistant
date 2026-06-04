import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show Provider;
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

@immutable
class CustomColors extends ThemeExtension<CustomColors> {
  final Color profit;
  final Color loss;
  final Color profitContainer;
  final Color lossContainer;
  final Color chartGrid;
  final Color accentBlue;
  final Color cardBackground;
  final Color aiCardBorder;

  const CustomColors({
    required this.profit,
    required this.loss,
    required this.profitContainer,
    required this.lossContainer,
    required this.chartGrid,
    required this.accentBlue,
    required this.cardBackground,
    required this.aiCardBorder,
  });

  Color pnlColor(double value) => value >= 0 ? profit : loss;

  @override
  CustomColors copyWith({
    Color? profit,
    Color? loss,
    Color? profitContainer,
    Color? lossContainer,
    Color? chartGrid,
    Color? accentBlue,
    Color? cardBackground,
    Color? aiCardBorder,
  }) {
    return CustomColors(
      profit: profit ?? this.profit,
      loss: loss ?? this.loss,
      profitContainer: profitContainer ?? this.profitContainer,
      lossContainer: lossContainer ?? this.lossContainer,
      chartGrid: chartGrid ?? this.chartGrid,
      accentBlue: accentBlue ?? this.accentBlue,
      cardBackground: cardBackground ?? this.cardBackground,
      aiCardBorder: aiCardBorder ?? this.aiCardBorder,
    );
  }

  @override
  CustomColors lerp(ThemeExtension<CustomColors>? other, double t) {
    if (other is! CustomColors) return this;
    return CustomColors(
      profit: Color.lerp(profit, other.profit, t)!,
      loss: Color.lerp(loss, other.loss, t)!,
      profitContainer: Color.lerp(profitContainer, other.profitContainer, t)!,
      lossContainer: Color.lerp(lossContainer, other.lossContainer, t)!,
      chartGrid: Color.lerp(chartGrid, other.chartGrid, t)!,
      accentBlue: Color.lerp(accentBlue, other.accentBlue, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      aiCardBorder: Color.lerp(aiCardBorder, other.aiCardBorder, t)!,
    );
  }
}

final customColorsProvider = Provider<CustomColors>((ref) {
  return const CustomColors(
    profit: PortfolioColors.profit,
    loss: PortfolioColors.loss,
    profitContainer: Color(0xFF14532D),
    lossContainer: Color(0xFF3D1515),
    chartGrid: PortfolioColors.chartGrid,
    accentBlue: PortfolioColors.accentBlue,
    cardBackground: PortfolioColors.surfaceCard,
    aiCardBorder: Color(0xFF3B82F6),
  );
});

extension CustomColorsX on BuildContext {
  CustomColors get customColors => Theme.of(this).extension<CustomColors>()!;
}
