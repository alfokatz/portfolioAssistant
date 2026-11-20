/// Próximo reporte de resultados programado para un ticker.
class EarningsCalendarEntry {
  const EarningsCalendarEntry({
    required this.ticker,
    required this.reportDate,
    this.fiscalQuarter,
    this.fiscalYear,
    this.epsEstimate,
    this.hour,
  });

  final String ticker;
  final DateTime reportDate;
  final int? fiscalQuarter;
  final int? fiscalYear;
  final double? epsEstimate;

  /// Momento del día según Finnhub: `bmo` (antes de la apertura), `amc`
  /// (después del cierre) o `dmh` (durante la sesión). Suele venir vacío.
  final String? hour;
}
