import 'package:portfolio_assistant/domain/entities/benchmark_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';

sealed class HomeAction {}

class SelectTimeRangeAction extends HomeAction {
  final ChartTimeRange range;

  SelectTimeRangeAction(this.range);
}

class ToggleShowAllPositionsAction extends HomeAction {
  final bool showAll;

  ToggleShowAllPositionsAction(this.showAll);
}

class LoadPortfolioAction extends HomeAction {
  final PortfolioSummary summary;
  final List<PortfolioHistoryPoint> history;
  final List<BenchmarkPoint> benchmark;
  final String? quoteError;
  final int closedPositionsCount;

  LoadPortfolioAction({
    required this.summary,
    required this.history,
    required this.benchmark,
    this.quoteError,
    this.closedPositionsCount = 0,
  });
}
