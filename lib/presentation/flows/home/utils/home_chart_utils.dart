import 'package:portfolio_assistant/domain/entities/benchmark_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_period_utils.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';

export 'package:portfolio_assistant/domain/utils/portfolio_period_utils.dart'
    show PeriodPnl;

class BenchmarkPeriodReturns {
  const BenchmarkPeriodReturns({
    required this.portfolioPercent,
    required this.sp500Percent,
    required this.differencePercent,
  });

  final double portfolioPercent;
  final double sp500Percent;
  final double differencePercent;
}

abstract final class HomeChartUtils {
  static List<PortfolioHistoryPoint> filterHistory(
    List<PortfolioHistoryPoint> points,
    ChartTimeRange range,
  ) {
    if (points.isEmpty) return points;
    final duration = range.duration;
    if (duration == null) return points;
    return PortfolioPeriodUtils.filterByDuration(points, duration);
  }

  /// Period return from portfolio history, excluding new investments as gains.
  static PeriodPnl periodPnlFromHistory(List<PortfolioHistoryPoint> points) {
    return PortfolioPeriodUtils.periodPnlFromHistory(points);
  }

  /// Total return vs what was invested ([totalCostBasis]).
  static PeriodPnl periodPnl({
    required double currentValue,
    required double totalCostBasis,
  }) {
    final absolute = currentValue - totalCostBasis;
    final percent =
        totalCostBasis > 0 ? (absolute / totalCostBasis) * 100 : 0.0;
    return PeriodPnl(absolute: absolute, percent: percent);
  }

  static List<BenchmarkPoint> filterBenchmark(
    List<BenchmarkPoint> points,
    ChartTimeRange range,
  ) {
    if (points.isEmpty) return points;
    final duration = range.duration;
    final filtered = duration == null
        ? points
        : () {
            final end = points.last.date;
            final start = end.subtract(duration);
            final slice =
                points.where((p) => !p.date.isBefore(start)).toList();
            return slice.length >= 2 ? slice : points;
          }();
    return renormalizeBenchmarkToPeriodStart(filtered);
  }

  /// Re-indexes both series to 100 at the first point of [points].
  static List<BenchmarkPoint> renormalizeBenchmarkToPeriodStart(
    List<BenchmarkPoint> points,
  ) {
    if (points.length < 2) return points;

    final basePortfolio = points.first.portfolioNormalized;
    final baseSp500 = points.first.sp500Normalized;
    if (basePortfolio <= 0 || baseSp500 <= 0) return points;

    return points
        .map(
          (p) => BenchmarkPoint(
            date: p.date,
            portfolioNormalized: (p.portfolioNormalized / basePortfolio) * 100,
            sp500Normalized: (p.sp500Normalized / baseSp500) * 100,
          ),
        )
        .toList();
  }

  static double? sp500PeriodReturnFromBenchmark(List<BenchmarkPoint> points) {
    if (points.length < 2) return null;

    final first = points.first;
    final last = points.last;
    if (first.sp500Normalized <= 0) return null;

    return (last.sp500Normalized / first.sp500Normalized - 1) * 100;
  }

  /// Portfolio return should come from [PeriodPnl] (vs cost basis, same as hero).
  static BenchmarkPeriodReturns? benchmarkComparisonReturns({
    required double portfolioPercent,
    required List<BenchmarkPoint> benchmarkPoints,
  }) {
    final sp500Percent = sp500PeriodReturnFromBenchmark(benchmarkPoints);
    if (sp500Percent == null) return null;

    return BenchmarkPeriodReturns(
      portfolioPercent: portfolioPercent,
      sp500Percent: sp500Percent,
      differencePercent: portfolioPercent - sp500Percent,
    );
  }

  /// Lightweight sparkline when per-ticker history is unavailable.
  static List<double> sparklineFromPrices({
    required double purchasePrice,
    required double currentPrice,
    int pointCount = 12,
  }) {
    if (pointCount < 2) return [currentPrice];
    return List<double>.generate(pointCount, (i) {
      final t = i / (pointCount - 1);
      return purchasePrice + (currentPrice - purchasePrice) * t;
    });
  }
}
