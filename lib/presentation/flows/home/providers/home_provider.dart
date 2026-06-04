import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/navigation/navigator.dart';
import 'package:portfolio_assistant/domain/entities/benchmark_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/use_cases/delete_positions_by_ticker_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_benchmark_comparison_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_history_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_summary_use_case.dart';
import 'package:portfolio_assistant/features/genui_core/models/gen_ui_flow_type.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/providers/base_state_notifier.dart';
import 'package:portfolio_assistant/features/portfolio_qa/nav/portfolio_qa_nav.dart';
import 'package:portfolio_assistant/presentation/flows/genui/nav/genui_nav.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_action.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_state.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_nav.dart';
import 'package:portfolio_assistant/presentation/flows/settings/nav/settings_nav.dart';

class HomeProvider extends BaseStateNotifier<HomeState, HomeAction> {
  final GetPortfolioSummaryUseCase getPortfolioSummaryUseCase;
  final GetPortfolioHistoryUseCase getPortfolioHistoryUseCase;
  final GetBenchmarkComparisonUseCase getBenchmarkComparisonUseCase;
  final DeletePositionsByTickerUseCase deletePositionsByTickerUseCase;
  final GetClosedPositionsUseCase getClosedPositionsUseCase;

  HomeProvider({
    required super.ref,
    required this.getPortfolioSummaryUseCase,
    required this.getPortfolioHistoryUseCase,
    required this.getBenchmarkComparisonUseCase,
    required this.deletePositionsByTickerUseCase,
    required this.getClosedPositionsUseCase,
  }) : super(state: HomeState());

  Future<void> init() async {
    await refresh();
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) showLoading();
    String? quoteError;

    final summaryResult = await getPortfolioSummaryUseCase();
    PortfolioSummary summary = const PortfolioSummary(
      totalValue: 0,
      totalCostBasis: 0,
      totalPnlAbsolute: 0,
      totalPnlPercent: 0,
      valuations: [],
    );

    summaryResult.fold(
      (error) => quoteError = error.message,
      (value) => summary = value,
    );

    final historyResult = await getPortfolioHistoryUseCase();
    final benchmarkResult = await getBenchmarkComparisonUseCase();
    final closedResult = await getClosedPositionsUseCase();

    final history = historyResult.fold((_) => <PortfolioHistoryPoint>[], (v) => v);
    final benchmark =
        benchmarkResult.fold((_) => <BenchmarkPoint>[], (v) => v);
    final closedCount =
        closedResult.fold((_) => 0, (list) => list.length);

    reducer(
      action: LoadPortfolioAction(
        summary: summary,
        history: history,
        benchmark: benchmark,
        quoteError: quoteError,
        closedPositionsCount: closedCount,
      ),
    );
    if (!silent) showContent();
  }

  Future<bool> deletePositionsForTicker(String ticker) async {
    showLoading();
    final result = await deletePositionsByTickerUseCase(params: ticker);
    return result.fold(
      (error) async {
        showContent();
        ref.read(alertProvider.notifier).showError(
              title: 'error'.tr(),
              message: error.message,
            );
        return false;
      },
      (_) async {
        await refresh(silent: true);
        showContent();
        return true;
      },
    );
  }

  void openAddPosition() {
    ref.read(navigationProvider.notifier).navigate(GotoAddPosition());
  }

  void openClosePosition(PositionValuation valuation) {
    ref.read(navigationProvider.notifier).navigate(
          GotoClosePosition(
            positionId: valuation.position.id,
            ticker: valuation.position.ticker,
            quantity: valuation.position.quantity,
            avgPurchasePrice: valuation.position.purchasePrice,
          ),
        );
  }

  void openClosedPositions() {
    ref.read(navigationProvider.notifier).navigate(GotoClosedPositions());
  }

  void openGenUiFlow(GenUiFlowType flowType) {
    ref.read(navigationProvider.notifier).navigate(
          GotoGenUiFlow(flowType: flowType),
        );
  }

  void openPortfolioQa({String? initialQuestion}) {
    ref.read(navigationProvider.notifier).navigate(
          GotoPortfolioQa(initialQuestion: initialQuestion),
        );
  }

  void openSettings() {
    ref.read(navigationProvider.notifier).navigate(GotoSettings());
  }

  void selectTimeRange(ChartTimeRange range) {
    reducer(action: SelectTimeRangeAction(range));
  }

  void showAllPositions() {
    reducer(action: ToggleShowAllPositionsAction(true));
  }

  @override
  void reducer({required HomeAction action}) {
    switch (action) {
      case LoadPortfolioAction():
        state = state.copyWith(
          summary: action.summary,
          history: action.history,
          benchmark: action.benchmark,
          quoteError: action.quoteError,
          closedPositionsCount: action.closedPositionsCount,
          clearQuoteError: action.quoteError == null,
        );
      case SelectTimeRangeAction():
        state = state.copyWith(selectedRange: action.range);
      case ToggleShowAllPositionsAction():
        state = state.copyWith(showAllPositions: action.showAll);
    }
  }
}

final homeProvider =
    StateNotifierProvider.autoDispose<HomeProvider, HomeState>(
  (ref) => HomeProvider(
    ref: ref,
    getPortfolioSummaryUseCase: ref.watch(getPortfolioSummaryUseCaseProvider),
    getPortfolioHistoryUseCase: ref.watch(getPortfolioHistoryUseCaseProvider),
    getBenchmarkComparisonUseCase:
        ref.watch(getBenchmarkComparisonUseCaseProvider),
    deletePositionsByTickerUseCase:
        ref.watch(deletePositionsByTickerUseCaseProvider),
    getClosedPositionsUseCase: ref.watch(getClosedPositionsUseCaseProvider),
  ),
);
