// Forma del gráfico del widget (§4.5): normalización, top 10, guarda de
// coherencia y respaldo `days`.
// Correr: flutter test test/features/home_widget/domain/widget_chart_builder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_chart_builder.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_phrase.dart';

final _t0 = DateTime.utc(2026, 11, 6, 14);

List<WidgetIntradayPoint> _series(List<double> prices) => [
  for (var i = 0; i < prices.length; i++)
    (time: _t0.add(Duration(minutes: 5 * i)), price: prices[i]),
];

WidgetChartHolding _h(
  String t, {
  double q = 1,
  double last = 100,
  double? prev = 100,
  List<double>? prices,
}) => WidgetChartHolding(
  ticker: t,
  quantity: q,
  lastPrice: last,
  prevClose: prev,
  intraday: prices == null ? null : _series(prices),
);

void main() {
  group('WidgetChartBuilder', () {
    test('intraday: normalized 0..1, last point is now, baseline inside', () {
      final chart = WidgetChartBuilder.build(
        holdings: [_h('A', last: 110, prices: [100, 102, 101, 105, 108, 110])],
        direction: WidgetDirection.up,
      )!;
      expect(chart.kind, 'intraday');
      expect(chart.points.first, closeTo(0.0, 0.001));
      expect(chart.points.last, 1.0);
      expect(chart.baseline, 0.0);
      for (final p in chart.points) {
        expect(p, inInclusiveRange(0, 1));
      }
    });

    test('flat series is all 0.5', () {
      final chart = WidgetChartBuilder.build(
        holdings: [_h('A', prices: [100, 100, 100, 100, 100, 100])],
        direction: WidgetDirection.flat,
      )!;
      expect(chart.points.every((p) => p == 0.5), isTrue);
      expect(chart.baseline, 0.5);
    });

    test('coherence guard: up but ends below the previous close -> days', () {
      final chart = WidgetChartBuilder.build(
        holdings: [_h('A', last: 95, prices: [100, 99, 98, 97, 96, 95])],
        direction: WidgetDirection.up,
        dailyValues: [10, 11, 12, 13],
      )!;
      expect(chart.kind, 'days');
      expect(chart.baseline, isNull);
    });

    test('days with fewer than 3 points -> null', () {
      expect(
        WidgetChartBuilder.build(
          holdings: const [],
          direction: WidgetDirection.up,
          dailyValues: [1, 2],
        ),
        isNull,
      );
    });

    test('days keeps the last 8 points', () {
      final chart = WidgetChartBuilder.build(
        holdings: const [],
        direction: WidgetDirection.up,
        dailyValues: [for (var i = 0; i < 12; i++) i.toDouble()],
      )!;
      expect(chart.points, hasLength(8));
      expect(chart.points.last, 1.0);
    });

    test('series with fewer than 6 points is not used', () {
      final chart = WidgetChartBuilder.build(
        holdings: [_h('A', prices: [100, 101, 102])],
        direction: WidgetDirection.up,
      );
      expect(chart, isNull);
    });

    test('a failed ticker stays fixed at its current price', () {
      final chart = WidgetChartBuilder.build(
        holdings: [
          _h('A', q: 10, last: 110, prices: [100, 102, 104, 106, 108, 110]),
          _h('B', q: 10, last: 50, prev: 50),
        ],
        direction: WidgetDirection.up,
      )!;
      expect(chart.kind, 'intraday');
      expect(chart.points.last, 1.0);
    });

    test('at most 48 points and the last one is kept', () {
      final prices = [for (var i = 0; i < 100; i++) 100 + i.toDouble()];
      final chart = WidgetChartBuilder.build(
        holdings: [_h('A', last: 199, prices: prices)],
        direction: WidgetDirection.up,
      )!;
      expect(chart.points, hasLength(48));
      expect(chart.points.last, 1.0);
    });

    test('only the 10 highest-value tickers request intraday', () {
      final holdings = [
        for (var i = 0; i < 12; i++) _h('T$i', last: 100.0 + i),
      ];
      final top = WidgetChartBuilder.topTickers(holdings);
      expect(top, hasLength(10));
      expect(top, isNot(contains('T0')));
      expect(top, isNot(contains('T1')));
    });
  });
}
