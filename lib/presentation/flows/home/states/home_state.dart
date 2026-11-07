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

  /// Hay una carga en curso y todavía no hay nada que mostrar: la Home
  /// muestra su skeleton (ver `HomeScreen`). Arranca en `true`: el primer
  /// frame no es "sin posiciones".
  final bool loading;

  /// [summary] viene del caché (lo último que se mostró) y todavía no llegó
  /// lo nuevo.
  final bool fromCache;

  HomeState({
    this.summary,
    this.history = const [],
    this.benchmark = const [],
    this.quoteError,
    this.selectedRange = ChartTimeRange.m1,
    this.showAllPositions = false,
    this.closedPositionsCount = 0,
    this.loading = true,
    this.fromCache = false,
  });

  HomeState copyWith({
    PortfolioSummary? summary,
    List<PortfolioHistoryPoint>? history,
    List<BenchmarkPoint>? benchmark,
    String? quoteError,
    ChartTimeRange? selectedRange,
    bool? showAllPositions,
    int? closedPositionsCount,
    bool? loading,
    bool? fromCache,
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
      loading: loading ?? this.loading,
      fromCache: fromCache ?? this.fromCache,
    );
  }
}
