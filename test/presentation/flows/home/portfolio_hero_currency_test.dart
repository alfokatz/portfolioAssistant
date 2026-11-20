// El encabezado de la Home en la moneda elegida (todo: total, variación y el
// recorrido del gráfico; el % no cambia) y el período 1D ("Hoy", con la hora
// al recorrer). Ya no hay una línea "Hoy …" aparte debajo de la variación.
// Correr: flutter test test/presentation/flows/home/portfolio_hero_currency_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_currency.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_money.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/portfolio_hero_section.dart';
import 'package:portfolio_assistant/presentation/shared/charts/portfolio_area_line_chart.dart';

const _summary = PortfolioSummary(
  totalValue: 1200,
  totalCostBasis: 1100,
  totalPnlAbsolute: 100,
  totalPnlPercent: 9.1,
  valuations: [],
);

Widget _app({
  required List<PortfolioHistoryPoint> history,
  ChartTimeRange range = ChartTimeRange.m1,
  DisplayMoney money = DisplayMoney.usd,
  String? periodLabel,
}) => MaterialApp(
  theme: ProviderContainer().read(themeDataLightProvider),
  home: Scaffold(
    body: SingleChildScrollView(
      child: PortfolioHeroSection(
        summary: _summary,
        history: history,
        periodPnlAbsolute: 100,
        periodPnlPercent: 10,
        selectedRange: range,
        onRangeSelected: (_) {},
        money: money,
        periodLabel: periodLabel,
      ),
    ),
  ),
);

final _daily = [
  for (var i = 0; i < 11; i++)
    PortfolioHistoryPoint(
      date: DateTime(2026, 9, 1 + i),
      totalValue: 1000 + 20.0 * i,
      totalCostBasis: 1000,
    ),
];

void main() {
  testWidgets('en pesos uruguayos: total y variación en esa moneda, el % '
      'igual', (tester) async {
    await tester.pumpWidget(
      _app(history: _daily, money: const DisplayMoney(DisplayCurrency.uyu, 40)),
    );
    expect(find.text('\$U 48,000'), findsOneWidget);
    expect(find.text('+\$U 4,000'), findsOneWidget);
    expect(find.text('+10.0%'), findsOneWidget);
    // Nada en dólares en el encabezado.
    expect(find.textContaining('\$1,200'), findsNothing);
  });

  testWidgets('recorriendo el gráfico, el valor del día también en pesos', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(history: _daily, money: const DisplayMoney(DisplayCurrency.uyu, 40)),
    );
    final chart = tester.getRect(find.byType(PortfolioAreaLineChart));
    final gesture = await tester.startGesture(
      chart.centerLeft + const Offset(5, 0),
    );
    await gesture.moveTo(chart.center);
    await tester.pump();
    // Día 5: 1100 dólares → 44.000 pesos; +100 → +4.000.
    expect(find.text('\$U 44,000'), findsOneWidget);
    expect(find.text('+\$U 4,000'), findsOneWidget);
    await gesture.up();
  });

  testWidgets('1D: dice "Hoy", no repite una línea aparte, y al recorrer '
      'muestra la hora', (tester) async {
    final intraday = [
      PortfolioHistoryPoint(
        date: DateTime(2026, 11, 16),
        totalValue: 1100,
        totalCostBasis: 1100,
      ),
      for (var i = 0; i < 10; i++)
        PortfolioHistoryPoint(
          date: DateTime(2026, 11, 17, 10, 30).add(Duration(minutes: 30 * i)),
          totalValue: 1100 + 10.0 * i,
          totalCostBasis: 1100,
        ),
    ];
    await tester.pumpWidget(
      _app(history: intraday, range: ChartTimeRange.d1, periodLabel: 'Hoy'),
    );
    expect(find.text('Hoy'), findsOneWidget);
    expect(find.text('1D'), findsOneWidget);
    expect(find.text('home_widget_period_today'), findsNothing);

    final chart = tester.getRect(find.byType(PortfolioAreaLineChart));
    final gesture = await tester.startGesture(
      chart.centerLeft + const Offset(5, 0),
    );
    await gesture.moveTo(chart.center);
    await tester.pump();
    expect(find.textContaining(RegExp(r'^\d{1,2}:\d{2}$')), findsOneWidget);
    await gesture.up();
  });
}
