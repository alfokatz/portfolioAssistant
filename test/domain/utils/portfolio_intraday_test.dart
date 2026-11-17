// El período "1D" de la Home: la serie del día arranca en el cierre anterior,
// termina exacto en el último punto del historial (misma variación que el
// widget y que PortfolioDayMove) y en el medio sigue la forma de las velas.
// Correr: flutter test test/domain/utils/portfolio_intraday_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_intraday.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_period_utils.dart';

import '../../helpers/property.dart';

final _prev = PortfolioHistoryPoint(
  date: DateTime(2026, 11, 16),
  totalValue: 1000,
  totalCostBasis: 900,
);
final _last = PortfolioHistoryPoint(
  date: DateTime(2026, 11, 17),
  totalValue: 1100,
  totalCostBasis: 900,
);

List<PriceCandle> _candles(List<double> closes) => [
  for (var i = 0; i < closes.length; i++)
    PriceCandle(
      date: DateTime(2026, 11, 17, 10).add(Duration(minutes: 5 * i)),
      close: closes[i],
    ),
];

void main() {
  group('PortfolioIntraday.series', () {
    test('without candles it is the straight line from the previous close', () {
      final s = PortfolioIntraday.series(
        previous: _prev,
        last: _last,
        holdings: const [
          IntradayHolding(ticker: 'AAPL', quantity: 10, lastPrice: 110),
        ],
      );
      expect(s, [_prev, _last]);
    });

    test('with too few candles it is also the straight line', () {
      final s = PortfolioIntraday.series(
        previous: _prev,
        last: _last,
        holdings: [
          IntradayHolding(
            ticker: 'AAPL',
            quantity: 10,
            lastPrice: 110,
            candles: _candles([100, 105, 110]),
          ),
        ],
      );
      expect(s, [_prev, _last]);
    });

    test('follows the shape of the day and ends exactly on the last point', () {
      final s = PortfolioIntraday.series(
        previous: _prev,
        last: _last,
        holdings: [
          IntradayHolding(
            ticker: 'AAPL',
            quantity: 10,
            lastPrice: 110,
            candles: _candles([100, 98, 96, 104, 108, 110]),
          ),
          // Sin velas: pesa fijo, no cambia la forma.
          const IntradayHolding(ticker: 'VOO', quantity: 1, lastPrice: 0),
        ],
      );
      expect(s.first, _prev);
      expect(s.last.totalValue, _last.totalValue);
      expect(s.length, 1 + 6);
      final values = [for (final p in s.skip(1)) p.totalValue];
      // Bajó, tocó fondo en la 3ª vela y subió hasta el cierre.
      expect(values[2], lessThan(values[0]));
      expect(values.last, greaterThan(values[2]));
      // Diferencias entre velas = cantidad × diferencia de precio.
      expect(values[1] - values[0], closeTo(10 * (98 - 100), 1e-9));
    });

    test('the change of the period is the same as the day move', () {
      final s = PortfolioIntraday.series(
        previous: _prev,
        last: _last,
        holdings: [
          IntradayHolding(
            ticker: 'AAPL',
            quantity: 10,
            lastPrice: 110,
            candles: _candles([100, 102, 104, 103, 107, 110]),
          ),
        ],
      );
      final move = PortfolioDayMove.compute(
        history: [_prev, _last],
        now: DateTime(2026, 11, 17, 15),
      );
      final pnl = PortfolioPeriodUtils.periodPnlFromHistory(s);
      expect(pnl.absolute, closeTo(move.absolute, 1e-9));
      expect(pnl.percent, closeTo(move.percent, 1e-9));
    });

    test('topTickers keeps the most valuable ones', () {
      final holdings = [
        for (var i = 0; i < 15; i++)
          IntradayHolding(ticker: 'T$i', quantity: 1, lastPrice: i.toDouble()),
      ];
      final top = PortfolioIntraday.topTickers(holdings);
      expect(top.length, PortfolioIntraday.maxTickers);
      expect(top.first, 'T14');
      expect(top.contains('T0'), isFalse);
    });
  });

  property<(List<IntradayHolding>, double, double)>(
    'la serie arranca en el cierre anterior, termina en el último punto y '
    'nunca tiene NaN',
    generate: (r) {
      final holdings = [
        for (final t in Gen.tickers(r, min: 1))
          IntradayHolding(
            ticker: t,
            quantity: Gen.quantity(r),
            lastPrice: Gen.amount(r) + 0.01,
            candles:
                r.nextBool()
                    ? null
                    : _candles([
                      for (var i = 0; i < r.nextInt(30); i++)
                        r.nextInt(10) == 0 ? 0 : 50 + r.nextDouble() * 100,
                    ]),
          ),
      ];
      return (holdings, Gen.amount(r), Gen.amount(r));
    },
    check: (input) {
      final (holdings, prevValue, lastValue) = input;
      final prev = PortfolioHistoryPoint(
        date: DateTime(2026, 11, 16),
        totalValue: prevValue,
        totalCostBasis: 500,
      );
      final last = PortfolioHistoryPoint(
        date: DateTime(2026, 11, 17),
        totalValue: lastValue,
        totalCostBasis: 500,
      );
      final s = PortfolioIntraday.series(
        previous: prev,
        last: last,
        holdings: holdings,
      );
      expect(s.length, greaterThanOrEqualTo(2));
      expect(s.first, prev);
      expect(s.last.totalValue, lastValue);
      expect(s.every((p) => p.totalValue.isFinite), isTrue);
      // Ordenada en el tiempo después del cierre anterior.
      for (var i = 2; i < s.length; i++) {
        expect(s[i].date.isBefore(s[i - 1].date), isFalse);
      }
    },
  );
}
