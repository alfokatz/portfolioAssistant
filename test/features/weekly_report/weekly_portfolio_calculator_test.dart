import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/report_week.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_portfolio_numbers.dart';

final _week = ReportWeek.ofMonday(DateTime(2026, 9, 21));

/// Vela diaria como la arma Yahoo: el timestamp de la apertura (13:30 UTC).
PriceCandle _c(int month, int day, double close) =>
    PriceCandle(date: DateTime.utc(2026, month, day, 13, 30), close: close);

/// Viernes anterior + las 5 ruedas de la semana, terminando en [end].
List<PriceCandle> _week5(double before, double end) => [
  _c(9, 18, before),
  _c(9, 21, before),
  _c(9, 22, before),
  _c(9, 23, (before + end) / 2),
  _c(9, 24, end),
  _c(9, 25, end),
];

Position _lot(
  String ticker,
  double qty,
  double price, {
  DateTime? bought,
  String id = 'x',
}) => Position(
  id: '$id-$ticker',
  ticker: ticker,
  quantity: qty,
  purchasePrice: price,
  purchaseDate: bought ?? DateTime(2026, 1, 10),
);

WeeklyPortfolioNumbers _compute(
  List<Position> lots,
  Map<String, List<PriceCandle>> candles, {
  List<PriceCandle> benchmark = const [],
  List<ClosedPosition> closed = const [],
}) => WeeklyPortfolioCalculator.compute(
  week: _week,
  lots: lots,
  candles: candles,
  benchmark: benchmark,
  closed: closed,
);

void main() {
  test(
    'weekly change is Friday vs previous Friday, ranked by contribution',
    () {
      final n = _compute(
        [_lot('AAPL', 10, 50), _lot('MSFT', 5, 150)],
        {'AAPL': _week5(100, 110), 'MSFT': _week5(200, 190)},
      );

      expect(n.valueStart, 2000);
      expect(n.valueEnd, 2050);
      expect(n.changeAbs, 50);
      expect(n.changePct, closeTo(2.5, 1e-9));
      expect(n.positions.map((p) => p.ticker), ['AAPL', 'MSFT']);
      expect(n.positions[0].contributionPp, closeTo(5, 1e-9));
      expect(n.positions[1].contributionPp, closeTo(-2.5, 1e-9));
      expect(n.positions[0].pricePct, closeTo(10, 1e-9));
      // Las contribuciones suman la variación de la cartera.
      expect(
        n.positions.fold(0.0, (a, p) => a + p.contributionPp),
        closeTo(n.changePct, 1e-9),
      );
      expect(n.tradingDays, 5);
    },
  );

  test('money added during the week is not counted as a gain', () {
    final n = _compute(
      [
        _lot('AAPL', 10, 50),
        // Compra el miércoles a 105; el viernes cierra en 110.
        _lot('AAPL', 10, 105, bought: DateTime(2026, 9, 23), id: 'y'),
      ],
      {'AAPL': _week5(100, 110)},
    );

    expect(n.newMoney, 1050);
    expect(n.valueStart, 1000 + 1050);
    expect(n.valueEnd, 2200);
    expect(n.changeAbs, closeTo(100 + 50, 1e-9));
    expect(n.positions.single.boughtThisWeek, isTrue);
    // El precio de la acción subió 10% en la semana, aunque la posición
    // (con la compra a mitad de semana) subió menos.
    expect(n.positions.single.pricePct, closeTo(10, 1e-9));
    expect(n.positions.single.positionPct, lessThan(10));
  });

  test('purchases after Friday are not part of the week', () {
    final n = _compute(
      [
        _lot('AAPL', 10, 50),
        _lot('NVDA', 1, 500, bought: DateTime(2026, 9, 26)),
      ],
      {'AAPL': _week5(100, 110), 'NVDA': _week5(500, 520)},
    );
    expect(n.positions.map((p) => p.ticker), ['AAPL']);
    expect(n.missingPrices, isEmpty);
  });

  test('a holiday week has 4 trading days', () {
    final spx = [
      _c(9, 18, 5000),
      _c(9, 21, 5010),
      // martes feriado
      _c(9, 23, 5020),
      _c(9, 24, 5030),
      _c(9, 25, 5050),
    ];
    final n = _compute(
      [_lot('AAPL', 10, 50)],
      {'AAPL': _week5(100, 110)},
      benchmark: spx,
    );
    expect(n.tradingDays, 4);
    expect(n.sp500Pct, closeTo(1, 1e-9));
    expect(n.vsSp500Pp, closeTo(10 - 1, 1e-9));
  });

  test('an empty portfolio gives empty numbers', () {
    final n = _compute([], {});
    expect(n.isEmpty, isTrue);
    expect(n.changePct, 0);
    expect(n.concentration, isNull);
  });

  test('a single position has no concentration block', () {
    final n = _compute([_lot('AAPL', 10, 50)], {'AAPL': _week5(100, 110)});
    expect(n.positions, hasLength(1));
    expect(n.concentration, isNull);
  });

  test('tickers with a dot (share classes) are normalized', () {
    final n = _compute(
      [_lot('brk.b', 2, 300), _lot('AAPL', 1, 100)],
      {'BRK.B': _week5(400, 420), 'AAPL': _week5(100, 100)},
    );
    expect(n.positions.first.ticker, 'BRK.B');
    expect(n.positions.first.pricePct, closeTo(5, 1e-9));
  });

  test('a ticker without prices is reported, not valued at zero', () {
    final n = _compute(
      [_lot('AAPL', 10, 50), _lot('ZZZZ', 3, 10)],
      {'AAPL': _week5(100, 110)},
    );
    expect(n.missingPrices, ['ZZZZ']);
    expect(n.valueStart, 1000);
  });

  test('concentration compares the top weight with four weeks before', () {
    final aapl = [_c(8, 28, 100), ..._week5(100, 200)];
    final msft = [_c(8, 28, 100), ..._week5(100, 100)];
    final n = _compute(
      [_lot('AAPL', 10, 50), _lot('MSFT', 10, 50)],
      {'AAPL': aapl, 'MSFT': msft},
    );
    expect(n.concentration!.ticker, 'AAPL');
    expect(n.concentration!.weightNow, closeTo(2 / 3, 1e-9));
    expect(n.concentration!.weightFourWeeksAgo, closeTo(0.5, 1e-9));
  });

  test('positions closed during the week are listed', () {
    final n = _compute(
      [_lot('AAPL', 10, 50)],
      {'AAPL': _week5(100, 110)},
      closed: [
        ClosedPosition(
          id: 'c1',
          ticker: 'tsla',
          quantity: 2,
          avgPurchasePrice: 100,
          closePrice: 150,
          closeDate: DateTime(2026, 9, 24),
          closedAt: DateTime(2026, 9, 24),
        ),
        ClosedPosition(
          id: 'c2',
          ticker: 'META',
          quantity: 1,
          avgPurchasePrice: 100,
          closePrice: 90,
          closeDate: DateTime(2026, 9, 10),
          closedAt: DateTime(2026, 9, 10),
        ),
      ],
    );
    expect(n.closedThisWeek.map((c) => c.ticker), ['TSLA']);
    expect(n.closedThisWeek.single.pnlPercent, closeTo(50, 1e-9));
  });

  test('no S&P figure when the benchmark has no candles that week', () {
    final n = _compute(
      [_lot('AAPL', 10, 50)],
      {'AAPL': _week5(100, 110)},
      benchmark: [_c(9, 17, 5000), _c(9, 18, 5000)],
    );
    expect(n.sp500Pct, isNull);
    expect(n.vsSp500Pp, isNull);
  });
}
