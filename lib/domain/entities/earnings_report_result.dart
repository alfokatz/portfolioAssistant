/// Resultado real vs. esperado por el mercado del último reporte publicado
/// de un ticker.
class EarningsReportResult {
  const EarningsReportResult({
    required this.ticker,
    required this.reportDate,
    this.epsActual,
    this.epsEstimate,
    this.revenueActual,
    this.revenueEstimate,
  });

  final String ticker;
  final DateTime reportDate;
  final double? epsActual;
  final double? epsEstimate;
  final double? revenueActual;
  final double? revenueEstimate;

  /// Solo se puede comparar real vs. esperado cuando Finnhub ya publicó
  /// ambos valores (algunos reportes recién listados aún no tienen actual).
  bool get hasEpsComparison => epsActual != null && epsEstimate != null;

  bool? get beatEstimate =>
      hasEpsComparison ? epsActual! >= epsEstimate! : null;
}
