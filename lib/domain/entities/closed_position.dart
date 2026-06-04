class ClosedPosition {
  final String id;
  final String ticker;
  final double quantity;
  final double avgPurchasePrice;
  final double closePrice;
  final DateTime closeDate;
  final DateTime closedAt;

  const ClosedPosition({
    required this.id,
    required this.ticker,
    required this.quantity,
    required this.avgPurchasePrice,
    required this.closePrice,
    required this.closeDate,
    required this.closedAt,
  });

  double get costBasis => quantity * avgPurchasePrice;

  double get proceeds => quantity * closePrice;

  double get pnlAbsolute => proceeds - costBasis;

  double get pnlPercent =>
      costBasis > 0 ? (pnlAbsolute / costBasis) * 100 : 0.0;
}
