import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/use_cases/get_position_lots_by_ticker_use_case.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/presentation/base/providers/base_state_notifier.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/position/states/position_detail_action.dart';
import 'package:portfolio_assistant/presentation/flows/position/states/position_detail_state.dart';

class PositionDetailProvider
    extends BaseStateNotifier<PositionDetailState, PositionDetailAction> {
  PositionDetailProvider({
    required super.ref,
    required this.ticker,
    required this.getPositionLotsByTickerUseCase,
  }) : super(state: const PositionDetailState());

  final String ticker;
  final GetPositionLotsByTickerUseCase getPositionLotsByTickerUseCase;

  Future<void> init() => load();

  Future<void> load() async {
    reducer(action: SetLoadingAction());

    final result = await getPositionLotsByTickerUseCase.call(params: ticker);
    result.fold(
      (error) => reducer(
            action: LoadLotsErrorAction(error.message ?? error.code),
          ),
      (lots) {
        reducer(
          action: LoadLotsSuccessAction(
            lots: lots,
            summary: _computeSummary(lots),
          ),
        );
        if (lots.isEmpty) {
          reducer(action: SetShouldPopAction(true));
        }
      },
    );
  }

  void closeLot(PositionValuation lot) {
    reducer(action: RequestCloseLotAction(lot));
  }

  void closeAll() {
    final summary = state.summary;
    if (summary == null) return;
    reducer(action: RequestCloseAllAction(summary));
  }

  Future<void> onCloseCompleted({required bool success}) async {
    reducer(action: ClearCloseRequestAction());
    if (!success) return;

    await ref.read(homeProvider.notifier).refresh(silent: true);
    await load();
  }

  void acknowledgePop() {
    reducer(action: SetShouldPopAction(false));
  }

  PositionValuation? _computeSummary(List<PositionValuation> lots) {
    if (lots.isEmpty) return null;
    final aggregated = PortfolioCalculator.aggregateByTicker(lots);
    return aggregated.isEmpty ? null : aggregated.first;
  }

  @override
  void reducer({required PositionDetailAction action}) {
    switch (action) {
      case SetLoadingAction():
        state = state.copyWith(
          isLoading: true,
          clearError: true,
        );
      case LoadLotsSuccessAction(:final lots, :final summary):
        state = state.copyWith(
          isLoading: false,
          lots: lots,
          summary: summary,
          clearError: true,
        );
      case LoadLotsErrorAction(:final message):
        state = state.copyWith(
          isLoading: false,
          lots: const [],
          clearSummary: true,
          errorMessage: message,
        );
      case RequestCloseLotAction(:final lot):
        state = state.copyWith(
          closeRequest: PositionDetailCloseRequest(
            positionId: lot.position.id,
            ticker: lot.position.ticker,
            quantity: lot.position.quantity,
            avgPurchasePrice: lot.position.purchasePrice,
          ),
        );
      case RequestCloseAllAction(:final summary):
        state = state.copyWith(
          closeRequest: PositionDetailCloseRequest(
            positionId: summary.position.ticker,
            ticker: summary.position.ticker,
            quantity: summary.position.quantity,
            avgPurchasePrice: summary.position.purchasePrice,
          ),
        );
      case ClearCloseRequestAction():
        state = state.copyWith(clearCloseRequest: true);
      case SetShouldPopAction(:final shouldPop):
        state = state.copyWith(shouldPop: shouldPop);
    }
  }
}

final positionDetailProvider = StateNotifierProvider.autoDispose
    .family<PositionDetailProvider, PositionDetailState, String>(
  (ref, ticker) => PositionDetailProvider(
    ref: ref,
    ticker: ticker,
    getPositionLotsByTickerUseCase:
        ref.watch(getPositionLotsByTickerUseCaseProvider),
  ),
);
