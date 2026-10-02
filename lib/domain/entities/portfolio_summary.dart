import 'package:portfolio_assistant/domain/entities/position_valuation.dart';

class PortfolioSummary {
  final double totalValue;
  final double totalCostBasis;
  final double totalPnlAbsolute;
  final double totalPnlPercent;
  /// Una por ticker (las compras del mismo ticker, agregadas).
  final List<PositionValuation> valuations;

  /// Cada compra por separado, valuada con el mismo precio que
  /// [valuations]. Es lo que muestra el detalle de una posición.
  final List<PositionValuation> lots;

  const PortfolioSummary({
    required this.totalValue,
    required this.totalCostBasis,
    required this.totalPnlAbsolute,
    required this.totalPnlPercent,
    required this.valuations,
    this.lots = const [],
  });
}
