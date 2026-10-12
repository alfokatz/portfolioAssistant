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
  test('movers go from the stock that rose the most to the one that rose '
      'the least, with the stock\'s weekly move', () {
    final movers = _report().movers;
    expect(movers.map((m) => m.ticker), ['AAPL', 'DASH', 'VOO']);
    expect(movers.map((m) => m.movePct.round()), [10, 4, 1]);
    expect(movers.first.role, MoverRole.addedMost);
    // Ninguna bajó: no hay "la que más bajó".
    expect(movers.any((m) => m.role == MoverRole.subtractedMost), isFalse);
  });

  testWidgets('a mid-week buy shows what the STOCK did in the week: DASH '
      '+4% in green with a green bar, even if the position lost since the '
      'purchase', (tester) async {
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
    final profit = context.customColors.profit;

    final dashPct = tester.widget<Text>(find.text('+4.0%'));
    expect(dashPct.style?.color, profit);
    expect(find.text('weekly_report_bought_this_week'), findsOneWidget);
    expect(find.textContaining('weekly_report_role_up_most'), findsOneWidget);

    // Las barras en el orden de la lista y todas verdes: las tres subieron.
    final bars = tester.widgetList<DivergingBar>(find.byType(DivergingBar));
    expect(bars.map((b) => b.value.sign), [1, 1, 1]);
    expect(bars.map((b) => b.value.round()), [10, 4, 1]);

    // Una fila que sigue en cartera abre la posición.
    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(3));
  });

  testWidgets('a report saved before (sorted by impact) also shows by the '
      'stock\'s move, with "la que más bajó" at the bottom', (tester) async {
    final saved = _report();
    final mixed = WeeklyReport.tryParse({
      ...saved.toJson(),
      'movers': [
        for (final m in [
          ReportMover(
            ticker: 'NFLX',
            movePct: -2,
            contributionPp: -1.5,
            boughtThisWeek: false,
          ),
          ReportMover(
            ticker: 'UBER',
            movePct: 5,
            contributionPp: -0.4,
            boughtThisWeek: true,
          ),
          ReportMover(
            ticker: 'AMZN',
            movePct: 4.3,
            contributionPp: 1.2,
            boughtThisWeek: false,
          ),
        ])
          m.toJson(),
      ],
    })!;
    await tester.binding.setSurfaceSize(const Size(390, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      reportApp(
        FixedWeeklyReportController(ready(mixed, seen: true)),
        openScreen: true,
        reduceMotion: true,
      ),
    );
    await tester.pumpAndSettle();
    final bars = tester.widgetList<DivergingBar>(find.byType(DivergingBar));
    expect(bars.map((b) => b.value), [5, 4.3, -2]);
    // UBER arriba: "La que más subió · Compraste esta semana".
    expect(find.textContaining('weekly_report_role_up_most'), findsOneWidget);
    expect(find.text('weekly_report_role_down_most'), findsOneWidget);
  });
}
