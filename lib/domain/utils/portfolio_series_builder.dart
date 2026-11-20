import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';

/// El historial diario del valor de la cartera (el del gráfico de la Home),
/// armado a partir de las posiciones y las velas diarias de cada ticker.
/// Es una función pura: la usan el repositorio de analytics y el widget de
/// la pantalla de inicio (que no puede tocar la red del repo).
abstract final class PortfolioSeriesBuilder {
  /// [candlesByTicker] va indexado por `position.ticker` tal cual (sin
  /// normalizar). Un ticker sin velas se valúa a su precio de compra.
  /// [now] es para tests; por defecto, la hora del teléfono.
  static List<PortfolioHistoryPoint> build(
    List<Position> positions,
    Map<String, List<PriceCandle>> candlesByTicker, {
    DateTime? now,
  }) {
    final startDate = seriesStart(positions, now: now);

    final allDates = <DateTime>{};
    for (final candles in candlesByTicker.values) {
      for (final c in candles) {
        if (!c.date.isBefore(startDate)) {
          allDates.add(DateTime(c.date.year, c.date.month, c.date.day));
        }
      }
    }

    final sortedDates = allDates.toList()..sort();

    final points = <PortfolioHistoryPoint>[];
    for (final date in sortedDates) {
      double total = 0;
      double costBasis = 0;
      for (final position in positions) {
        // Sin fecha de compra conocida: cuenta como que ya estaba (no como
        // una compra del día de la importación).
        if (position.purchaseDateKnown && position.purchaseDate.isAfter(date)) {
          continue;
        }
        final candles = candlesByTicker[position.ticker] ?? const [];
        final price = closeOnOrBefore(candles, date) ?? position.purchasePrice;
        total += position.quantity * price;
        costBasis += position.costBasis;
      }
      if (total > 0) {
        points.add(
          PortfolioHistoryPoint(
            date: date,
            totalValue: total,
            totalCostBasis: costBasis,
          ),
        );
      }
    }
    return points;
  }

  /// Desde cuándo se grafica: la primera compra con fecha. Si hay compras
  /// sin fecha (un bróker que no la informa), como mínimo el último año: se
  /// ve cómo se movió lo que tiene en vez de una línea que arranca hoy.
  static DateTime seriesStart(List<Position> positions, {DateTime? now}) {
    final known = [
      for (final p in positions)
        if (p.purchaseDateKnown) p.purchaseDate,
    ];
    final yearAgo = (now ?? DateTime.now()).subtract(const Duration(days: 365));
    if (known.isEmpty) return yearAgo;
    final earliest = known.reduce((a, b) => a.isBefore(b) ? a : b);
    final anyUnknown = positions.any((p) => !p.purchaseDateKnown);
    return anyUnknown && yearAgo.isBefore(earliest) ? yearAgo : earliest;
  }

  /// El cierre de la última vela que no es posterior a [date].
  static double? closeOnOrBefore(List<PriceCandle> candles, DateTime date) {
    PriceCandle? best;
    for (final c in candles) {
      if (c.date.isAfter(date)) continue;
      if (best == null || c.date.isAfter(best.date)) {
        best = c;
      }
    }
    return best?.close;
  }
}
