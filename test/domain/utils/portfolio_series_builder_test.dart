// Regresión de PortfolioSeriesBuilder (extraído de
// PortfolioAnalyticsRepositoryImpl): con posiciones y velas fijas da el
// mismo historial que daba el repositorio.
// Correr: flutter test test/domain/utils/portfolio_series_builder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_series_builder.dart';

Position _p(
  String ticker,
  double qty,
  double price,
  DateTime date, {
  bool known = true,
}) => Position(
  id: ticker,
  ticker: ticker,
  quantity: qty,
  purchasePrice: price,
  purchaseDate: date,
  purchaseDateKnown: known,
);

PriceCandle _c(int day, double close) =>
    PriceCandle(date: DateTime(2026, 11, day), close: close);

void main() {
  final now = DateTime(2026, 11, 5, 12);

  group('PortfolioSeriesBuilder.build', () {
    test('values each day with the close on or before it', () {
      final positions = [
        _p('AAA', 2, 10, DateTime(2026, 11, 1)),
        _p('BBB', 1, 100, DateTime(2026, 11, 1)),
      ];
      final candles = {
        'AAA': [_c(1, 10), _c(2, 11), _c(4, 12)],
        'BBB': [_c(1, 100), _c(3, 90)],
      };
      final series = PortfolioSeriesBuilder.build(positions, candles, now: now);

      expect(series.map((p) => p.date.day), [1, 2, 3, 4]);
      // día 1: 2*10 + 100; día 2: 2*11 + 100; día 3: 2*11 + 90; día 4: 2*12 + 90
      expect(series.map((p) => p.totalValue), [120, 122, 112, 114]);
      expect(series.every((p) => p.totalCostBasis == 120), isTrue);
    });

    test('a lot bought later does not count before its purchase date', () {
      final positions = [
        _p('AAA', 1, 10, DateTime(2026, 11, 1)),
        _p('BBB', 1, 50, DateTime(2026, 11, 3)),
      ];
      final candles = {
        'AAA': [_c(1, 10), _c(2, 10), _c(3, 10)],
        'BBB': [_c(1, 50), _c(2, 50), _c(3, 55)],
      };
      final series = PortfolioSeriesBuilder.build(positions, candles, now: now);

      expect(series.map((p) => p.totalValue), [10, 10, 65]);
      expect(series.map((p) => p.totalCostBasis), [10, 10, 60]);
    });

    test('a ticker without candles is valued at its purchase price', () {
      final positions = [
        _p('AAA', 1, 10, DateTime(2026, 11, 1)),
        _p('BBB', 2, 7, DateTime(2026, 11, 1)),
      ];
      final candles = {
        'AAA': [_c(1, 10), _c(2, 12)],
      };
      final series = PortfolioSeriesBuilder.build(positions, candles, now: now);

      expect(series.map((p) => p.totalValue), [24, 26]);
    });

    test('unknown purchase dates count as already held, from a year back', () {
      final positions = [_p('AAA', 1, 10, DateTime(2026, 11, 5), known: false)];
      final candles = {
        'AAA': [PriceCandle(date: DateTime(2025, 12, 1), close: 8), _c(4, 12)],
      };
      final series = PortfolioSeriesBuilder.build(positions, candles, now: now);

      expect(series.map((p) => p.totalValue), [8, 12]);
    });

    test('empty without candles', () {
      expect(
        PortfolioSeriesBuilder.build([_p('AAA', 1, 10, DateTime(2026))], {}),
        isEmpty,
      );
    });
  });

  group('PortfolioSeriesBuilder.seriesStart', () {
    test('first dated purchase', () {
      final positions = [
        _p('A', 1, 1, DateTime(2026, 3, 1)),
        _p('B', 1, 1, DateTime(2026, 5, 1)),
      ];
      expect(
        PortfolioSeriesBuilder.seriesStart(positions, now: now),
        DateTime(2026, 3, 1),
      );
    });

    test('with an undated purchase, at least a year back', () {
      final positions = [
        _p('A', 1, 1, DateTime(2026, 3, 1)),
        _p('B', 1, 1, DateTime(2026, 11, 5), known: false),
      ];
      expect(
        PortfolioSeriesBuilder.seriesStart(positions, now: now),
        now.subtract(const Duration(days: 365)),
      );
    });
  });
}
