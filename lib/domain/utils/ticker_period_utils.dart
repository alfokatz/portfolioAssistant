import 'package:portfolio_assistant/domain/entities/price_candle.dart';

/// Movimiento de precio de un ticker en un intervalo.
class TickerPeriodMove {
  const TickerPeriodMove({
    required this.priceStart,
    required this.priceEnd,
    required this.changeAbs,
    required this.changePct,
    required this.hasSufficientHistory,
  });

  static const empty = TickerPeriodMove(
    priceStart: 0,
    priceEnd: 0,
    changeAbs: 0,
    changePct: 0,
    hasSufficientHistory: false,
  );

  final double priceStart;
  final double priceEnd;
  final double changeAbs;
  final double changePct;
  final bool hasSufficientHistory;
}

/// Cálculo de retornos por ticker a partir de velas diarias.
abstract final class TickerPeriodUtils {
  static List<PriceCandle> _strictFilterByDuration(
    List<PriceCandle> candles,
    Duration duration,
  ) {
    if (candles.isEmpty) return candles;

    final end = candles.last.date;
    final start = end.subtract(duration);
    return candles.where((c) => !c.date.isBefore(start)).toList();
  }

  static List<PriceCandle> filterByDuration(
    List<PriceCandle> candles,
    Duration duration,
  ) {
    final filtered = _strictFilterByDuration(candles, duration);
    return filtered.length >= 2 ? filtered : candles;
  }

  static TickerPeriodMove moveForDuration(
    List<PriceCandle> candles,
    Duration duration,
  ) {
    if (candles.isEmpty) return TickerPeriodMove.empty;

    // Filtro estricto (sin el fallback permisivo de [filterByDuration]):
    // si no hay al menos 2 velas *dentro* de la ventana pedida, no hay
    // suficiente granularidad para nombrar el resultado como ese período
    // ("último día", etc.) — el fallback permisivo siempre encuentra >=2
    // puntos en el historial completo, lo que enmascaraba este caso y
    // terminaba reportando el cambio histórico total como si fuera diario.
    final filtered = _strictFilterByDuration(candles, duration);
    if (filtered.length < 2) {
      final price = candles.last.close;
      return TickerPeriodMove(
        priceStart: price,
        priceEnd: price,
        changeAbs: 0,
        changePct: 0,
        hasSufficientHistory: false,
      );
    }

    final priceStart = filtered.first.close;
    final priceEnd = filtered.last.close;
    final changeAbs = priceEnd - priceStart;
    final changePct = priceStart > 0 ? (changeAbs / priceStart) * 100 : 0.0;

    return TickerPeriodMove(
      priceStart: priceStart,
      priceEnd: priceEnd,
      changeAbs: changeAbs,
      changePct: changePct,
      hasSufficientHistory: true,
    );
  }
}
