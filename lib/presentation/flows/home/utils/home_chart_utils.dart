import 'package:portfolio_assistant/domain/entities/benchmark_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_period_utils.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';

export 'package:portfolio_assistant/domain/utils/portfolio_period_utils.dart'
    show PeriodPnl;

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
    if (duration == null) return points;

    final end = points.last.date;
    final start = end.subtract(duration);
    final filtered = points.where((p) => !p.date.isBefore(start)).toList();
    return filtered.length >= 2 ? filtered : points;
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
