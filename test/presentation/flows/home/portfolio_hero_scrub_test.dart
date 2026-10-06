import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/portfolio_hero_section.dart';
import 'package:portfolio_assistant/presentation/shared/charts/portfolio_area_line_chart.dart';

/// 11 días: el valor sube 10 por día; a mitad del período entran 100 de
/// plata nueva (sube el costo), que no tiene que contar como ganancia.
final _history = [
  for (var i = 0; i < 11; i++)
    PortfolioHistoryPoint(
      date: DateTime(2026, 9, 1 + i),
      totalValue: 1000 + 10.0 * i + (i >= 5 ? 100 : 0),
      totalCostBasis: 1000 + (i >= 5 ? 100 : 0),
    ),
];

Widget _app() => MaterialApp(
  theme: ProviderContainer().read(themeDataLightProvider),
  home: Scaffold(
    body: SingleChildScrollView(
      child: PortfolioHeroSection(
        summary: const PortfolioSummary(
          totalValue: 1200,
          totalCostBasis: 1100,
          totalPnlAbsolute: 100,
          totalPnlPercent: 9.1,
          valuations: [],
        ),
        history: _history,
        periodPnlAbsolute: 100,
        periodPnlPercent: 10,
        selectedRange: ChartTimeRange.m1,
        onRangeSelected: (_) {},
      ),
    ),
  ),
);

void main() {
  testWidgets('dragging shows that day (value, change since the start, '
      'date); releasing goes back to today and the period', (tester) async {
    await tester.pumpWidget(_app());
    expect(find.text('\$1,200.00'), findsOneWidget);
    expect(find.text('home_range_m1'), findsOneWidget);

    final chart = tester.getRect(find.byType(PortfolioAreaLineChart));
    // Al medio del gráfico: el día 5 (índice 5 de 0..10).
    final gesture = await tester.startGesture(chart.centerLeft + const Offset(5, 0));
    await gesture.moveTo(chart.center);
    await tester.pump();

    expect(find.text('\$1,150.00'), findsOneWidget);
    // +50 de suba real; los 100 que entraron no son ganancia.
    expect(find.text('+\$50.00'), findsOneWidget);
    expect(find.text('home_range_m1'), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('\$1,200.00'), findsOneWidget);
    expect(find.text('home_range_m1'), findsOneWidget);
  });
}
