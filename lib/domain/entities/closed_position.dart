import 'package:portfolio_assistant/domain/entities/position.dart';

class ClosedPosition {
  final String id;
  final String ticker;
  final double quantity;
  final double avgPurchasePrice;
  final double closePrice;
  final DateTime closeDate;
  final DateTime closedAt;
  final PositionSource source;

  /// Ganancia neta que informó el bróker (eToro: ya con comisiones y
  /// dividendos). Si está, manda sobre el cálculo de Porty.
  final double? realizedPnl;

  const ClosedPosition({
    required this.id,
    required this.ticker,
    required this.quantity,
    required this.avgPurchasePrice,
    required this.closePrice,
    required this.closeDate,
    required this.closedAt,
    this.source = PositionSource.manual,
    this.realizedPnl,
  });

  double get costBasis => quantity * avgPurchasePrice;

  double get proceeds => quantity * closePrice;

  double get pnlAbsolute => realizedPnl ?? proceeds - costBasis;

  double get pnlPercent =>
      costBasis > 0 ? (pnlAbsolute / costBasis) * 100 : 0.0;

  /// El P&L viene del bróker (incluye comisiones), no de precio × cantidad.
  bool get hasBrokerPnl => realizedPnl != null;
}
