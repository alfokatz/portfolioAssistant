class PortfolioSnapshotPosition {
  final String ticker;
  final double quantity;
  final double purchasePrice;
  final double currentPrice;
  final double marketValue;
  final double weight;
  final double pnlPercent;
  final double pnlAbsolute;

  const PortfolioSnapshotPosition({
    required this.ticker,
    required this.quantity,
    required this.purchasePrice,
    required this.currentPrice,
    required this.marketValue,
    required this.weight,
    required this.pnlPercent,
    required this.pnlAbsolute,
  });

  Map<String, dynamic> toJson() => {
        'ticker': ticker,
        'quantity': quantity,
        'purchasePrice': purchasePrice,
        'currentPrice': currentPrice,
        'marketValue': marketValue,
        'weight': weight,
        'pnlPercent': pnlPercent,
        'pnlAbsolute': pnlAbsolute,
      };
}

class PortfolioSnapshot {
  final double totalValue;
  final double totalPnlPercent;
  final double totalPnlAbsolute;
  final DateTime asOf;
  final List<PortfolioSnapshotPosition> positions;

  const PortfolioSnapshot({
    required this.totalValue,
    required this.totalPnlPercent,
    required this.totalPnlAbsolute,
    required this.asOf,
    required this.positions,
  });

  Map<String, dynamic> toJson() => {
        'totalValue': totalValue,
        'totalPnlPercent': totalPnlPercent,
        'totalPnlAbsolute': totalPnlAbsolute,
        'asOf': asOf.toIso8601String(),
        'positions': positions.map((p) => p.toJson()).toList(),
      };

  String get jsonString => toJson().toString();
}
