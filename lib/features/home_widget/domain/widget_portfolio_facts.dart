import 'package:portfolio_assistant/domain/entities/price_candle.dart';

/// Una tenencia con lo que hace falta para "lo que más se movió" y "la
/// posición más grande". Sin cantidades: solo valor y variación.
class WidgetPositionFact {
  const WidgetPositionFact({
    required this.ticker,
    required this.marketValue,
    this.dayPct,
  });

  final String ticker;
  final double marketValue;

  /// Variación % del último día (último cierre vs anterior); `null` si no
  /// hay dos velas.
  final double? dayPct;
}

class WidgetMoverFact {
  const WidgetMoverFact({required this.ticker, required this.pct});

  final String ticker;
  final double pct;
}

class WidgetBiggestFact {
  const WidgetBiggestFact({required this.ticker, required this.weightPct});

  final String ticker;

  /// Peso sobre el valor total, en puntos (0..100).
  final double weightPct;
}

/// Datos de la cartera que arman las novedades `mover` y `biggest`. Puro.
abstract final class WidgetPortfolioFacts {
  /// Variación % del último cierre contra el anterior, de las velas diarias
  /// ya cargadas. `null` si hay menos de dos o el anterior no es positivo.
  static double? dayPct(List<PriceCandle> candles) {
    if (candles.length < 2) return null;
    final sorted = [...candles]..sort((a, b) => a.date.compareTo(b.date));
    final last = sorted[sorted.length - 1].close;
    final prev = sorted[sorted.length - 2].close;
    if (!(prev > 0)) return null;
    return (last - prev) / prev * 100;
  }

  /// La tenencia con mayor |% del último día|; empate → más peso.
  static WidgetMoverFact? mover(List<WidgetPositionFact> positions) {
    WidgetPositionFact? best;
    for (final p in positions) {
      final pct = p.dayPct;
      if (pct == null || p.ticker.isEmpty) continue;
      final current = best;
      if (current == null) {
        best = p;
        continue;
      }
      final cmp = pct.abs().compareTo(current.dayPct!.abs());
      if (cmp > 0 || (cmp == 0 && p.marketValue > current.marketValue)) {
        best = p;
      }
    }
    if (best == null) return null;
    return WidgetMoverFact(ticker: best.ticker, pct: best.dayPct!);
  }

  /// La de más valor, solo con 2 o más posiciones con valor.
  static WidgetBiggestFact? biggest(List<WidgetPositionFact> positions) {
    final valued = [
      for (final p in positions)
        if (p.marketValue > 0 && p.ticker.isNotEmpty) p,
    ];
    if (valued.length < 2) return null;
    final total = valued.fold<double>(0, (sum, p) => sum + p.marketValue);
    valued.sort((a, b) {
      final byValue = b.marketValue.compareTo(a.marketValue);
      return byValue != 0 ? byValue : a.ticker.compareTo(b.ticker);
    });
    return WidgetBiggestFact(
      ticker: valued.first.ticker,
      weightPct: valued.first.marketValue / total * 100,
    );
  }
}
