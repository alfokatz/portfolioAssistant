import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/benchmark_point.dart';
import 'package:portfolio_assistant/presentation/flows/home/utils/home_chart_utils.dart';

void main() {
  group('HomeChartUtils benchmark', () {
    final points = [
      BenchmarkPoint(
        date: DateTime(2024, 1, 1),
        portfolioNormalized: 100,
        sp500Normalized: 100,
      ),
      BenchmarkPoint(
        date: DateTime(2024, 6, 1),
        portfolioNormalized: 3085,
        sp500Normalized: 103,
      ),
    ];

    test('renormalizeBenchmarkToPeriodStart indexes both series at 100', () {
      final normalized =
          HomeChartUtils.renormalizeBenchmarkToPeriodStart(points);

      expect(normalized.first.portfolioNormalized, 100);
      expect(normalized.first.sp500Normalized, 100);
      expect(normalized.last.portfolioNormalized, closeTo(3085, 0.01));
      expect(normalized.last.sp500Normalized, closeTo(103, 0.01));
    });

    test('sp500PeriodReturnFromBenchmark uses only index movement', () {
      final normalized =
          HomeChartUtils.renormalizeBenchmarkToPeriodStart(points);

      expect(
        HomeChartUtils.sp500PeriodReturnFromBenchmark(normalized),
        closeTo(3, 0.01),
      );
    });

    test('benchmarkComparisonReturns uses portfolio percent from cost basis', () {
      final normalized =
          HomeChartUtils.renormalizeBenchmarkToPeriodStart(points);
      final returns = HomeChartUtils.benchmarkComparisonReturns(
        portfolioPercent: 12.5,
        benchmarkPoints: normalized,
      );

      expect(returns, isNotNull);
      expect(returns!.portfolioPercent, 12.5);
      expect(returns.sp500Percent, closeTo(3, 0.01));
      expect(returns.differencePercent, closeTo(9.5, 0.01));
    });
  });
}
