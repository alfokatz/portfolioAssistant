import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';

/// Una tenencia para el gráfico del día: cuánto tiene, a cuánto está y sus
/// velas intradía (`null` o vacías si no se pidieron o fallaron: queda fija
/// en [lastPrice]).
class IntradayHolding {
  const IntradayHolding({
    required this.ticker,
    required this.quantity,
    required this.lastPrice,
    this.candles,
  });

  final String ticker;
  final double quantity;
  final double lastPrice;
  final List<PriceCandle>? candles;

  double get value => quantity * lastPrice;
}

/// El período "1D" de la Home: el valor de la cartera a lo largo del día.
/// Puro. Misma idea que el gráfico del widget de inicio (las velas de 5 min
/// de los tickers de más valor; el resto, fijo en su precio).
abstract final class PortfolioIntraday {
  /// Solo estos tickers (los de más valor) piden velas intradía.
  static const maxTickers = 10;

  /// Con menos velas que esto la forma del día no dice nada.
  static const minPoints = 6;

  /// Los [maxTickers] de más valor: a quiénes pedirles velas.
  static List<String> topTickers(List<IntradayHolding> holdings) {
    final sorted = [...holdings]..sort((a, b) => b.value.compareTo(a.value));
    return [for (final h in sorted.take(maxTickers)) h.ticker];
  }

  /// La serie del día para el gráfico y la variación: arranca en el cierre
  /// anterior ([previous], el anteúltimo punto del historial diario) y
  /// termina exacto en [last] (el último), así la variación del período es
  /// la misma que la del widget y la de "Hoy". En el medio, la forma del día
  /// con las velas; corrida para que empalme con [last] (las tenencias sin
  /// velas pesan fijas y no cambian la forma).
  ///
  /// Sin velas suficientes devuelve `[previous, last]`: una recta, pero con
  /// los números correctos.
  static List<PortfolioHistoryPoint> series({
    required PortfolioHistoryPoint previous,
    required PortfolioHistoryPoint last,
    required List<IntradayHolding> holdings,
  }) {
    final withCandles = [
      for (final h in holdings)
        if ((h.candles?.where((c) => c.close > 0).length ?? 0) >= minPoints) h,
    ];
    if (withCandles.isEmpty) return [previous, last];

    List<PriceCandle> sortedCandles(IntradayHolding h) => [
      for (final c in h.candles!)
        if (c.close > 0) c,
    ]..sort((a, b) => a.date.compareTo(b.date));

    final series = {for (final h in withCandles) h: sortedCandles(h)};
    // La grilla: las velas del ticker con más puntos.
    final grid = [
      for (final c in series.values.reduce(
        (a, b) => a.length >= b.length ? a : b,
      ))
        c.date,
    ];

    double priceAt(IntradayHolding h, DateTime time) {
      final candles = series[h];
      if (candles == null) return h.lastPrice;
      var price = candles.first.close;
      for (final c in candles) {
        if (c.date.isAfter(time)) break;
        price = c.close;
      }
      return price;
    }

    final values = [
      for (final t in grid)
        holdings.fold<double>(0, (sum, h) => sum + h.quantity * priceAt(h, t)),
    ];
    if (values.isEmpty || values.any((v) => !v.isFinite)) {
      return [previous, last];
    }
    final shift = last.totalValue - values.last;
    return [
      previous,
      for (var i = 0; i < grid.length - 1; i++)
        PortfolioHistoryPoint(
          date: grid[i],
          totalValue: values[i] + shift,
          totalCostBasis: last.totalCostBasis,
        ),
      PortfolioHistoryPoint(
        date: grid.last,
        totalValue: last.totalValue,
        totalCostBasis: last.totalCostBasis,
      ),
    ];
  }
}
