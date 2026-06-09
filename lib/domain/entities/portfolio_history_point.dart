class PortfolioHistoryPoint {
  final DateTime date;
  final double totalValue;
  final double totalCostBasis;

  const PortfolioHistoryPoint({
    required this.date,
    required this.totalValue,
    required this.totalCostBasis,
  });

  double get unrealizedPnl => totalValue - totalCostBasis;
}
