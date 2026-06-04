class BenchmarkPoint {
  final DateTime date;
  final double portfolioNormalized;
  final double sp500Normalized;

  const BenchmarkPoint({
    required this.date,
    required this.portfolioNormalized,
    required this.sp500Normalized,
  });
}
