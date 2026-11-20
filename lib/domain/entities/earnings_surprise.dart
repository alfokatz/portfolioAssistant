/// Un trimestre ya reportado: EPS real vs. consenso — Finnhub
/// `/stock/earnings`. A diferencia del calendario, este endpoint casi
/// siempre trae el `actual` de los últimos trimestres.
class EarningsSurprise {
  const EarningsSurprise({
    required this.ticker,
    required this.period,
    this.fiscalQuarter,
    this.fiscalYear,
    this.epsActual,
    this.epsEstimate,
    this.surprisePercent,
  });

  final String ticker;

  /// Cierre del trimestre fiscal (no la fecha en que se publicó).
  final DateTime period;
  final int? fiscalQuarter;
  final int? fiscalYear;
  final double? epsActual;
  final double? epsEstimate;
  final double? surprisePercent;

  bool get hasEpsComparison => epsActual != null && epsEstimate != null;

  bool? get beatEstimate =>
      hasEpsComparison ? epsActual! >= epsEstimate! : null;
}
