import 'package:portfolio_assistant/domain/entities/benchmark_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';

class HomeState {
  final PortfolioSummary? summary;
  final List<PortfolioHistoryPoint> history;
  final List<BenchmarkPoint> benchmark;
  final String? quoteError;
  final ChartTimeRange selectedRange;
  final bool showAllPositions;
  final int closedPositionsCount;

  HomeState({
    this.summary,
    this.history = const [],
    this.benchmark = const [],
    this.quoteError,
    this.selectedRange = ChartTimeRange.m1,
    this.showAllPositions = false,
    this.closedPositionsCount = 0,
  });

  HomeState copyWith({
    PortfolioSummary? summary,
    List<PortfolioHistoryPoint>? history,
    List<BenchmarkPoint>? benchmark,
    String? quoteError,
    ChartTimeRange? selectedRange,
    bool? showAllPositions,
    int? closedPositionsCount,
    bool clearQuoteError = false,
  }) {
    return HomeState(
      summary: summary ?? this.summary,
      history: history ?? this.history,
      benchmark: benchmark ?? this.benchmark,
      quoteError: clearQuoteError ? null : (quoteError ?? this.quoteError),
      selectedRange: selectedRange ?? this.selectedRange,
      showAllPositions: showAllPositions ?? this.showAllPositions,
      closedPositionsCount:
          closedPositionsCount ?? this.closedPositionsCount,
    );
  }
}
