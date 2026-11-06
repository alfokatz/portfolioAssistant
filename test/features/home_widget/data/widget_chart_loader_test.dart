import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_chart_loader.dart';

Position _pos(String ticker, double quantity) => Position(
  id: ticker,
  ticker: ticker,
  quantity: quantity,
  purchasePrice: 10,
  purchaseDate: DateTime(2026, 1, 2),
);

final _yesterday = DateTime(2026, 11, 5);
final _today = DateTime(2026, 11, 6);

/// Velas diarias: ayer cerró en [prev], hoy va en [last].
List<PriceCandle> _daily(double prev, double last) => [
  PriceCandle(date: _yesterday, close: prev),
  PriceCandle(date: _today, close: last),
];

/// Intradía de hoy: [n] puntos de 5 min, de [from] a [to].
List<PriceCandle> _intraday(double from, double to, {int n = 8}) => [
  for (var i = 0; i < n; i++)
    PriceCandle(
      date: _today.add(Duration(hours: 10, minutes: 5 * i)),
      close: from + (to - from) * i / (n - 1),
    ),
];

void main() {
  test('intraday: shape of the day with the previous close as baseline', () async {
    final requested = <String>[];
    final chart = await loadWidgetChart(
      positions: [_pos('AAA', 2), _pos('AAA', 1), _pos('BBB', 1)],
      dailyCandles: {'AAA': _daily(100, 110), 'BBB': _daily(50, 50)},
      movePercent: 5,
      dailyValues: const [1, 2, 3, 4],
      loadIntraday: (t) async {
        requested.add(t);
        return t == 'AAA' ? _intraday(101, 110) : const [];
      },
    );
    expect(chart, isNotNull);
    expect(chart!.kind, 'intraday');
    expect(chart.points, hasLength(8));
    expect(chart.points.last, 1.0);
    // Cierre anterior: 3×100 + 50 = 350, por debajo de toda la serie.
    expect(chart.baseline, 0.0);
    expect(requested.toSet(), {'AAA', 'BBB'});
  });

  test('intraday that contradicts the direction falls back to days', () async {
    final chart = await loadWidgetChart(
      positions: [_pos('AAA', 1)],
      dailyCandles: {'AAA': _daily(100, 90)},
      movePercent: 3, // sube, pero el intradía cierra abajo del cierre anterior
      dailyValues: const [1, 2, 3],
      loadIntraday: (_) async => _intraday(99, 90),
    );
    expect(chart?.kind, 'days');
  });

  test('a failing or slow intraday does not break: days or null', () async {
    final failing = await loadWidgetChart(
      positions: [_pos('AAA', 1)],
      dailyCandles: {'AAA': _daily(100, 101)},
      movePercent: 1,
      dailyValues: const [1, 2, 3],
      loadIntraday: (_) async => throw StateError('red'),
    );
    expect(failing?.kind, 'days');

    final slow = await loadWidgetChart(
      positions: [_pos('AAA', 1)],
      dailyCandles: {'AAA': _daily(100, 101)},
      movePercent: 1,
      dailyValues: const [1, 2],
      loadIntraday: (_) => Future.delayed(
        const Duration(seconds: 1),
        () => _intraday(100, 101),
      ),
      timeout: const Duration(milliseconds: 10),
    );
    expect(slow, isNull);
  });

  test('without intraday loader: days from the Home history', () async {
    final chart = await loadWidgetChart(
      positions: [_pos('AAA', 1)],
      dailyCandles: {'AAA': _daily(100, 101)},
      movePercent: 1,
      dailyValues: [for (var i = 0; i < 12; i++) i.toDouble()],
      loadIntraday: null,
    );
    expect(chart?.kind, 'days');
    expect(chart?.points, hasLength(8));
    expect(chart?.baseline, isNull);
  });
}
