import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/benchmark_point.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/benchmark_comparison_card.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/portfolio_qa_entry_card.dart';

/// Sin easy_localization cargado, `.tr()` devuelve la key.
Widget _app(Widget child) => MaterialApp(
  theme: ProviderContainer().read(themeDataLightProvider),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

List<BenchmarkPoint> _sp500(double changePct) => [
  BenchmarkPoint(
    date: DateTime(2026, 9, 6),
    portfolioNormalized: 100,
    sp500Normalized: 100,
  ),
  BenchmarkPoint(
    date: DateTime(2026, 10, 6),
    portfolioNormalized: 100,
    sp500Normalized: 100 + changePct,
  ),
];

void main() {
  group('Contra el mercado', () {
    testWidgets('says the period and who won', (tester) async {
      await tester.pumpWidget(
        _app(
          BenchmarkComparisonCard(
            portfolioPercent: -0.6,
            benchmarkPoints: _sp500(2.1),
            range: ChartTimeRange.m1,
          ),
        ),
      );
      expect(find.text('home_range_m1'), findsOneWidget);
      expect(find.text('home_benchmark_behind'), findsOneWidget);
      expect(find.text('-0.6%'), findsOneWidget);
      expect(find.text('+2.1%'), findsOneWidget);
    });

    testWidgets('ahead, and almost the same', (tester) async {
      await tester.pumpWidget(
        _app(
          BenchmarkComparisonCard(
            portfolioPercent: 4,
            benchmarkPoints: _sp500(1),
            range: ChartTimeRange.all,
          ),
        ),
      );
      expect(find.text('home_benchmark_ahead'), findsOneWidget);
      expect(find.text('home_range_all'), findsOneWidget);

      await tester.pumpWidget(
        _app(
          BenchmarkComparisonCard(
            portfolioPercent: 1.1,
            benchmarkPoints: _sp500(1),
            range: ChartTimeRange.w1,
          ),
        ),
      );
      expect(find.text('home_benchmark_tie'), findsOneWidget);
    });
  });

  testWidgets('Porty: the header opens the chat, a suggestion asks it', (
    tester,
  ) async {
    var opened = 0;
    String? asked;
    await tester.pumpWidget(
      _app(
        PortfolioQaEntryCard(
          onOpen: () => opened++,
          onAsk: (q) => asked = q,
          suggestions: const ['¿Cómo viene VOO?'],
        ),
      ),
    );
    await tester.tap(find.text('home_porty_entry_title'));
    expect(opened, 1);
    await tester.tap(find.text('¿Cómo viene VOO?'));
    expect(asked, '¿Cómo viene VOO?');
  });
}
