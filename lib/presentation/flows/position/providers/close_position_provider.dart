import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/use_cases/close_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_price_on_date_use_case.dart';
import 'package:portfolio_assistant/presentation/flows/position/states/close_position_state.dart';

class ClosePositionProvider extends StateNotifier<ClosePositionState> {
  ClosePositionProvider({
    required this.args,
    required this.getPriceOnDateUseCase,
  }) : super(
          ClosePositionState(
            closeDate: DateTime.now(),
            sellAmountText: args.quantity.toString(),
          ),
        );

  final ClosePositionArgs args;
  final GetPriceOnDateUseCase getPriceOnDateUseCase;

  Future<void> init() => fetchPriceForDate();

  Future<void> setCloseDate(DateTime date) async {
    state = state.copyWith(closeDate: date);
    await fetchPriceForDate();
  }

  Future<void> fetchPriceForDate() async {
    state = state.copyWith(loadingPrice: true);

    final result = await getPriceOnDateUseCase.call(
      params: GetPriceOnDateParams(
        ticker: args.ticker,
        date: state.closeDate,
      ),
    );

    result.fold(
      (_) => state = state.copyWith(loadingPrice: false),
      (price) {
        state = state.copyWith(
          loadingPrice: false,
          priceText: price > 0 ? price.toStringAsFixed(2) : state.priceText,
        );
      },
    );
  }

  void setScope(CloseScope scope) {
    state = state.copyWith(
      scope: scope,
      sellAmountText:
          scope == CloseScope.all
              ? args.quantity.toString()
              : state.sellAmountText,
    );
  }

  void setSellMode(SellInputMode mode) {
    state = state.copyWith(sellMode: mode);
  }

  void setPriceText(String value) {
    state = state.copyWith(priceText: value);
  }

  void setSellAmountText(String value) {
    state = state.copyWith(sellAmountText: value);
  }

  double? closePrice() => double.tryParse(state.priceText);

  double? sharesToSell() {
    if (state.scope == CloseScope.all) return args.quantity;

    final price = closePrice();
    if (price == null || price <= 0) return null;

    final raw = double.tryParse(state.sellAmountText);
    if (raw == null || raw <= 0) return null;

    return state.sellMode == SellInputMode.shares ? raw : (raw / price);
  }

  Future<ClosePositionSaveResult> save({
    required ClosePositionUseCase closePositionUseCase,
  }) async {
    final shares = sharesToSell();
    final price = closePrice();
    if (shares == null || price == null || shares <= 0 || price <= 0) {
      return const ClosePositionSaveResult.invalidInput();
    }

    state = state.copyWith(saving: true);

    final result = await closePositionUseCase.call(
      params: ClosePositionParams(
        positionId: args.positionId,
        quantity: shares,
        closePrice: price,
        closeDate: state.closeDate,
      ),
    );

    state = state.copyWith(saving: false);

    return result.fold(
      ClosePositionSaveResult.failure,
      (_) => const ClosePositionSaveResult.success(),
    );
  }
}

sealed class ClosePositionSaveResult {
  const ClosePositionSaveResult();

  const factory ClosePositionSaveResult.invalidInput() =
      ClosePositionInvalidInputResult;
  const factory ClosePositionSaveResult.success() = ClosePositionSuccessResult;
  const factory ClosePositionSaveResult.failure(HttpError error) =
      ClosePositionFailureResult;
}

final class ClosePositionInvalidInputResult extends ClosePositionSaveResult {
  const ClosePositionInvalidInputResult();
}

final class ClosePositionSuccessResult extends ClosePositionSaveResult {
  const ClosePositionSuccessResult();
}

final class ClosePositionFailureResult extends ClosePositionSaveResult {
  const ClosePositionFailureResult(this.error);

  final HttpError error;
}

final closePositionProvider = StateNotifierProvider.autoDispose
    .family<ClosePositionProvider, ClosePositionState, ClosePositionArgs>(
  (ref, args) => ClosePositionProvider(
    args: args,
    getPriceOnDateUseCase: ref.watch(getPriceOnDateUseCaseProvider),
  ),
);
