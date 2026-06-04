import 'package:portfolio_assistant/domain/entities/position_valuation.dart';

class PortfolioSummary {
  final double totalValue;
  final double totalCostBasis;
  final double totalPnlAbsolute;
  final double totalPnlPercent;
  final List<PositionValuation> valuations;

  const PortfolioSummary({
    required this.totalValue,
    required this.totalCostBasis,
    required this.totalPnlAbsolute,
    required this.totalPnlPercent,
    required this.valuations,
  });
}
