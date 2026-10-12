import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_portfolio_numbers.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_draft.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_input.dart';
import 'package:portfolio_assistant/features/weekly_report/view/weekly_report_chart.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/charts/diverging_bar.dart';

import 'weekly_report_fixtures.dart' show fixtureWeek;
import 'weekly_report_ui_test.dart' show FixedWeeklyReportController, ready, reportApp;

PriceCandle _c(int day, double close) =>
    PriceCandle(date: DateTime.utc(2026, 9, day, 13, 30), close: close);

/// Viernes anterior, lunes a jueves en [mid] y viernes en [end].
List<PriceCandle> _week(double before, double mid, double end) => [
  _c(18, before),
  _c(21, before),
  _c(22, mid),
  _c(23, mid),
  _c(24, mid),
  _c(25, end),
];

Position _lot(String t, double qty, double price, DateTime date) => Position(
  id: '$t-${date.day}',
  ticker: t,
  quantity: qty,
  purchasePrice: price,
  purchaseDate: date,
);

/// AAPL de antes (+10%), VOO de antes (+1%) y DASH comprada el martes
/// después de que saltara: la acción sube 4% en la semana, pero desde la
/// compra (108) baja a 104.
WeeklyReport _report() {
  final numbers = WeeklyPortfolioCalculator.compute(
    week: fixtureWeek,
    lots: [
      _lot('AAPL', 10, 50, DateTime(2026, 1, 5)),
      _lot('VOO', 4, 400, DateTime(2026, 1, 5)),
      _lot('DASH', 10, 108, DateTime(2026, 9, 22)),
    ],
    candles: {
      'AAPL': _week(100, 105, 110),
      'VOO': _week(500, 502, 505),
      'DASH': _week(100, 108, 104),
    },
  );
  return WeeklyReport.compose(
    input: WeeklyReportInput(
      numbers: numbers,
      news: const [],
      upcomingEarnings: const [],
      newsFailed: false,
      earningsFailed: false,
    ),
    draft: WeeklyReportDraft.empty,
    variant: WeeklyReportVariant.full,
  );
}

void main() {
  test('movers go from the biggest gain to the biggest loss', () {
    final movers = _report().movers;
    expect(movers.map((m) => m.ticker), ['AAPL', 'VOO', 'DASH']);
    expect(movers.first.role, MoverRole.addedMost);
    expect(movers.last.role, MoverRole.subtractedMost);
  });

  test('a mid-week buy keeps both numbers: the stock\'s week and the '
      'position since the purchase', () {
    final dash = _report().movers.firstWhere((m) => m.ticker == 'DASH');
    expect(dash.movePct, closeTo(4, 1e-9)); // la acción, viernes a viernes
    expect(dash.positionPct, closeTo((104 - 108) / 108 * 100, 1e-9));
    expect(dash.contributionPp, lessThan(0));
    // Sobrevive al guardado.
    final stored = ReportMover.fromJson(dash.toJson());
    expect(stored.positionPct, dash.positionPct);
  });

  testWidgets('the row shows what the bar draws: DASH in red (its position '
      'lost), with the stock\'s +4% as context', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      reportApp(
        FixedWeeklyReportController(ready(_report(), seen: true)),
        openScreen: true,
        reduceMotion: true,
        holdings: const {'AAPL': 1100, 'VOO': 2020, 'DASH': 1040},
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(WeeklyImpactBar).first);
    final loss = context.customColors.loss;

    final dashPct = tester.widget<Text>(find.text('-3.7%'));
    expect(dashPct.style?.color, loss);
    expect(find.textContaining('weekly_report_stock_move'), findsOneWidget);

    // Las barras en el orden de la lista: la última, la de DASH, en rojo.
    final bars = tester.widgetList<DivergingBar>(find.byType(DivergingBar));
    expect(bars.map((b) => b.value.sign), [1, 1, -1]);

    // Una fila que sigue en cartera abre la posición.
    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(3));
  });
}
