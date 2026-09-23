/// Próximo reporte de resultados programado para un ticker.
class EarningsCalendarEntry {
  const EarningsCalendarEntry({
    required this.ticker,
    required this.reportDate,
    this.fiscalQuarter,
    this.fiscalYear,
    this.epsEstimate,
  });

  final String ticker;
  final DateTime reportDate;
  final int? fiscalQuarter;
  final int? fiscalYear;
  final double? epsEstimate;
}
