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
  static List<PriceCandle> filterByDuration(
    List<PriceCandle> candles,
    Duration duration,
  ) {
    if (candles.isEmpty) return candles;

    final end = candles.last.date;
    final start = end.subtract(duration);
    final filtered =
        candles.where((c) => !c.date.isBefore(start)).toList();
    return filtered.length >= 2 ? filtered : candles;
  }

  static TickerPeriodMove moveForDuration(
    List<PriceCandle> candles,
    Duration duration,
  ) {
    if (candles.isEmpty) return TickerPeriodMove.empty;

    final filtered = filterByDuration(candles, duration);
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
    final changePct =
        priceStart > 0 ? (changeAbs / priceStart) * 100 : 0.0;

    return TickerPeriodMove(
      priceStart: priceStart,
      priceEnd: priceEnd,
      changeAbs: changeAbs,
      changePct: changePct,
      hasSufficientHistory: true,
    );
  }
}
