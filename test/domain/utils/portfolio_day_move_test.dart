// PortfolioDayMove: la variación del último día (la de la línea "Hoy" de la
// Home y la del widget de la pantalla de inicio).
// Correr: flutter test test/domain/utils/portfolio_day_move_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';

PortfolioHistoryPoint _pt(int day, double value, double cost) =>
    PortfolioHistoryPoint(
      date: DateTime(2026, 11, day),
      totalValue: value,
      totalCostBasis: cost,
    );

Position _pos(String t, double qty, {DateTime? date}) => Position(
  id: t,
  ticker: t,
  quantity: qty,
  purchasePrice: 10,
  purchaseDate: date ?? DateTime(2026, 10, 1),
);

PriceCandle _c(int day, double close) =>
    PriceCandle(date: DateTime(2026, 11, day), close: close);

void main() {
  final wednesday = DateTime(2026, 11, 4, 15);

  group('PortfolioDayMove.compute', () {
    test('today: the last point is today', () {
      final move = PortfolioDayMove.compute(
        history: [_pt(3, 1000, 900), _pt(4, 1020, 900)],
        now: wednesday,
      );
      expect(move.period, DayMovePeriod.today);
      expect(move.absolute, closeTo(20, 1e-9));
      // Dietz: 20 / (1000 + 0).
      expect(move.percent, closeTo(2, 1e-9));
      expect(move.asOfDay, DateTime(2026, 11, 4));
    });

    test('last close: the last point is from another day', () {
      final move = PortfolioDayMove.compute(
        history: [_pt(5, 1000, 900), _pt(6, 990, 900)],
        now: DateTime(2026, 11, 8), // domingo
      );
      expect(move.period, DayMovePeriod.lastClose);
      expect(move.absolute, closeTo(-10, 1e-9));
    });

    test('money bought on the last day is not counted as a gain', () {
      final move = PortfolioDayMove.compute(
        history: [_pt(3, 1000, 900), _pt(4, 1500, 1400)],
        now: wednesday,
      );
      expect(move.absolute, closeTo(0, 1e-9));
    });

    test('mixed portfolio with a saturday point: the move is from friday', () {
      // Cripto 24/7: hay punto de sábado; el último día es sábado.
      final move = PortfolioDayMove.compute(
        history: [_pt(5, 1000, 900), _pt(6, 1010, 900), _pt(7, 1005, 900)],
        now: DateTime(2026, 11, 7, 10),
      );
      expect(move.period, DayMovePeriod.today);
      expect(move.absolute, closeTo(-5, 1e-9));
    });

    test('fewer than two points: zero move, no contributor', () {
      final one = PortfolioDayMove.compute(
        history: [_pt(4, 1000, 1000)],
        now: wednesday,
      );
      expect(one.absolute, 0);
      expect(one.percent, 0);
      expect(one.period, DayMovePeriod.today);

      final none = PortfolioDayMove.compute(history: const [], now: wednesday);
      expect(none.period, DayMovePeriod.lastClose);
      expect(none.asOfDay, isNull);
    });
  });

  group('PortfolioDayMove top contributor', () {
    final history = [_pt(3, 1000, 900), _pt(4, 1030, 900)];

    PortfolioDayMove move(
      List<Position> positions,
      Map<String, List<PriceCandle>> candles, {
      List<PortfolioHistoryPoint>? hist,
    }) => PortfolioDayMove.compute(
      history: hist ?? history,
      positions: positions,
      candlesByTicker: candles,
      now: wednesday,
    );

    test('up: the ticker that added the most', () {
      final m = move(
        [_pos('AAA', 10), _pos('BBB', 1)],
        {
          'AAA': [_c(3, 10), _c(4, 12)], // +20
          'BBB': [_c(3, 100), _c(4, 110)], // +10
        },
      );
      expect(m.topContributor?.ticker, 'AAA');
      expect(m.topContributor?.amount, closeTo(20, 1e-9));
    });

    test('down: the ticker that took away the most', () {
      final m = move(
        [_pos('AAA', 10), _pos('BBB', 1)],
        {
          'AAA': [_c(3, 10), _c(4, 9)], // -10
          'BBB': [_c(3, 100), _c(4, 80)], // -20
        },
        hist: [_pt(3, 1000, 900), _pt(4, 970, 900)],
      );
      expect(m.topContributor?.ticker, 'BBB');
    });

    test('lots of the same ticker add up', () {
      final m = move(
        [_pos('AAA', 5), _pos('AAA', 5), _pos('BBB', 1)],
        {
          'AAA': [_c(3, 10), _c(4, 11)], // 10 * 1 = +10
          'BBB': [_c(3, 100), _c(4, 105)], // +5
        },
      );
      expect(m.topContributor?.ticker, 'AAA');
      expect(m.topContributor?.amount, closeTo(10, 1e-9));
    });

    test('a tie has no top contributor', () {
      final m = move(
        [_pos('AAA', 1), _pos('BBB', 1)],
        {
          'AAA': [_c(3, 10), _c(4, 15)],
          'BBB': [_c(3, 20), _c(4, 25)],
        },
      );
      expect(m.topContributor, isNull);
    });

    test('missing data for a ticker has no top contributor', () {
      final noCandles = move(
        [_pos('AAA', 1), _pos('BBB', 1)],
        {
          'AAA': [_c(3, 10), _c(4, 15)],
        },
      );
      expect(noCandles.topContributor, isNull);

      final noPrevious = move(
        [_pos('AAA', 1)],
        {
          'AAA': [_c(4, 15)],
        },
      );
      expect(noPrevious.topContributor, isNull);
    });

    test('a lot bought on the last day does not count', () {
      final m = move(
        [_pos('AAA', 10), _pos('NEW', 100, date: DateTime(2026, 11, 4))],
        {
          'AAA': [_c(3, 10), _c(4, 11)],
          // sin vela del día anterior: no importa, no la tenía
        },
      );
      expect(m.topContributor?.ticker, 'AAA');
    });

    test('a contributor against the direction of the move is not named', () {
      final m = move(
        [_pos('AAA', 1)],
        {
          'AAA': [_c(3, 10), _c(4, 9)], // baja, pero el total sube
        },
      );
      expect(m.topContributor, isNull);
    });

    test('flat day has none', () {
      final m = move(
        [_pos('AAA', 1)],
        {
          'AAA': [_c(3, 10), _c(4, 10)],
        },
        hist: [_pt(3, 1000, 900), _pt(4, 1000, 900)],
      );
      expect(m.topContributor, isNull);
    });
  });
}
