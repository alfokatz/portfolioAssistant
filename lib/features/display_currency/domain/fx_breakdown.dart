import 'package:portfolio_assistant/domain/entities/price_candle.dart';

/// Una compra, en dólares: lo que costó, lo que vale hoy y cuándo se compró.
class FxLot {
  const FxLot({
    required this.costUsd,
    required this.valueUsd,
    required this.purchaseDate,
  });

  final double costUsd;
  final double valueUsd;
  final DateTime purchaseDate;
}

/// La cartera en otra moneda y de dónde sale la ganancia.
///
/// Para cada compra, con el tipo de cambio del día de compra (`fx_d`) y el
/// de hoy (`fx_0`), en unidades de la moneda por dólar:
/// - costo = costo USD × fx_d; valor = valor USD × fx_0;
/// - por las inversiones = (valor USD − costo USD) × fx_0;
/// - por el tipo de cambio = costo USD × (fx_0 − fx_d).
///
/// Las dos partes suman la ganancia en la moneda.
class FxBreakdown {
  const FxBreakdown({
    required this.rateNow,
    required this.value,
    required this.cost,
    required this.investmentEffect,
    required this.currencyEffect,
    required this.lotsWithoutHistory,
  });

  final double rateNow;
  final double value;
  final double cost;
  final double investmentEffect;
  final double currencyEffect;

  /// Compras anteriores al histórico de tipos de cambio: se usó el primer
  /// tipo de cambio conocido.
  final int lotsWithoutHistory;

  double get gain => value - cost;

  double get gainPercent => cost > 0 ? gain / cost * 100 : 0;

  /// [history]: cierres diarios del tipo de cambio (cualquier orden).
  static FxBreakdown compute({
    required List<FxLot> lots,
    required double rateNow,
    required List<PriceCandle> history,
  }) {
    final sorted = [
      for (final c in history)
        if (c.close > 0) c,
    ]..sort((a, b) => a.date.compareTo(b.date));

    var value = 0.0;
    var cost = 0.0;
    var investment = 0.0;
    var currency = 0.0;
    var missing = 0;
    for (final lot in lots) {
      final (rate, found) = rateOn(sorted, lot.purchaseDate, rateNow);
      if (!found) missing++;
      value += lot.valueUsd * rateNow;
      cost += lot.costUsd * rate;
      investment += (lot.valueUsd - lot.costUsd) * rateNow;
      currency += lot.costUsd * (rateNow - rate);
    }
    return FxBreakdown(
      rateNow: rateNow,
      value: value,
      cost: cost,
      investmentEffect: investment,
      currencyEffect: currency,
      lotsWithoutHistory: missing,
    );
  }

  /// El cierre del día [date] o del último día hábil anterior. Si [date] es
  /// anterior a todo el histórico, el primero conocido (`found` = false);
  /// sin histórico, [fallback].
  static (double, bool) rateOn(
    List<PriceCandle> sortedHistory,
    DateTime date,
    double fallback,
  ) {
    if (sortedHistory.isEmpty) return (fallback, false);
    final day = DateTime(date.year, date.month, date.day);
    PriceCandle? best;
    for (final c in sortedHistory) {
      final d = DateTime(c.date.year, c.date.month, c.date.day);
      if (d.isAfter(day)) break;
      best = c;
    }
    if (best == null) return (sortedHistory.first.close, false);
    return (best.close, true);
  }
}
