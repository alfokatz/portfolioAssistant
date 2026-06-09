import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/utils/ticker_period_utils.dart';

void main() {
  group('TickerPeriodUtils', () {
    final candles = [
      PriceCandle(date: DateTime(2026, 6, 1), close: 100),
      PriceCandle(date: DateTime(2026, 6, 5), close: 110),
      PriceCandle(date: DateTime(2026, 6, 9), close: 95),
    ];

    test('moveForDuration computes change from filtered window', () {
      final move = TickerPeriodUtils.moveForDuration(
        candles,
        const Duration(days: 7),
      );

      expect(move.hasSufficientHistory, isTrue);
      expect(move.priceStart, 110);
      expect(move.priceEnd, 95);
      expect(move.changeAbs, -15);
      expect(move.changePct, closeTo(-13.64, 0.01));
    });

    test('moveForDuration returns insufficient history for single candle', () {
      final move = TickerPeriodUtils.moveForDuration(
        [candles.last],
        const Duration(days: 7),
      );

      expect(move.hasSufficientHistory, isFalse);
      expect(move.changePct, 0);
    });

    test('filterByDuration keeps points within window', () {
      final filtered = TickerPeriodUtils.filterByDuration(
        candles,
        const Duration(days: 5),
      );

      expect(filtered.length, 2);
      expect(filtered.first.close, 110);
      expect(filtered.last.close, 95);
    });
  });
}
