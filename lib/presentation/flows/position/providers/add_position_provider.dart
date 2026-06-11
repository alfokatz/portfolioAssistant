import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/use_cases/add_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_current_price_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_price_on_date_use_case.dart';
import 'package:portfolio_assistant/presentation/flows/position/states/add_position_state.dart';

class AddPositionProvider extends StateNotifier<AddPositionState> {
  AddPositionProvider({
    required AddPositionArgs args,
    required this.getPriceOnDateUseCase,
    required this.getCurrentPriceUseCase,
  }) : super(
          AddPositionState(
            purchaseDate: DateTime.now(),
            datePicked: args.prefilledPrice != null,
            tickerText: args.prefilledTicker ?? '',
            quantityText: args.prefilledQuantity?.toString() ?? '',
            priceText: args.prefilledPrice?.toString() ?? '',
          ),
        );

  final GetPriceOnDateUseCase getPriceOnDateUseCase;
  final GetCurrentPriceUseCase getCurrentPriceUseCase;

  Future<void> setPurchaseDate(DateTime date) async {
    state = state.copyWith(purchaseDate: date, datePicked: true);
    await fetchPriceForDate();
  }

  Future<void> fetchPriceForDate() async {
    final ticker = state.tickerText.trim();
    if (ticker.isEmpty || !state.datePicked) return;

    state = state.copyWith(loadingPrice: true);

    final result = await getPriceOnDateUseCase.call(
      params: GetPriceOnDateParams(ticker: ticker, date: state.purchaseDate),
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

    await fetchCurrentPrice();
  }

  Future<void> fetchCurrentPrice() async {
    final ticker = state.tickerText.trim();
    if (ticker.isEmpty) return;

    state = state.copyWith(loadingCurrent: true);

    final result = await getCurrentPriceUseCase.call(params: ticker);

    result.fold(
      (_) => state = state.copyWith(loadingCurrent: false, clearCurrentPrice: true),
      (price) => state = state.copyWith(
        loadingCurrent: false,
        currentPrice: price,
      ),
    );
  }

  void setMode(BuyInputMode mode) {
    state = state.copyWith(mode: mode);
  }

  void setTickerText(String value) {
    state = state.copyWith(tickerText: value);
  }

  void setQuantityText(String value) {
    state = state.copyWith(quantityText: value);
  }

  void setPriceText(String value) {
    state = state.copyWith(priceText: value);
  }

  double? purchasePrice() => double.tryParse(state.priceText);

  double? shares() {
    final price = purchasePrice();
    if (price == null || price <= 0) return null;

    final raw = double.tryParse(state.quantityText);
    if (raw == null || raw <= 0) return null;

    return state.mode == BuyInputMode.shares ? raw : (raw / price);
  }

  Future<AddPositionSaveResult> save({
    required AddPositionUseCase addPositionUseCase,
  }) async {
    final shareCount = shares();
    final price = purchasePrice();
    if (shareCount == null || price == null) {
      return const AddPositionSaveResult.invalidInput();
    }

    state = state.copyWith(saving: true);

    final result = await addPositionUseCase.call(
      params: AddPositionParams(
        ticker: state.tickerText,
        quantity: shareCount,
        purchasePrice: price,
        purchaseDate: state.purchaseDate,
      ),
    );

    state = state.copyWith(saving: false);

    return result.fold(
      AddPositionSaveResult.failure,
      (_) => const AddPositionSaveResult.success(),
    );
  }
}

sealed class AddPositionSaveResult {
  const AddPositionSaveResult();

  const factory AddPositionSaveResult.invalidInput() =
      AddPositionInvalidInputResult;
  const factory AddPositionSaveResult.success() = AddPositionSuccessResult;
  const factory AddPositionSaveResult.failure(HttpError error) =
      AddPositionFailureResult;
}

final class AddPositionInvalidInputResult extends AddPositionSaveResult {
  const AddPositionInvalidInputResult();
}

final class AddPositionSuccessResult extends AddPositionSaveResult {
  const AddPositionSuccessResult();
}

final class AddPositionFailureResult extends AddPositionSaveResult {
  const AddPositionFailureResult(this.error);

  final HttpError error;
}

final addPositionProvider = StateNotifierProvider.autoDispose
    .family<AddPositionProvider, AddPositionState, AddPositionArgs>(
  (ref, args) => AddPositionProvider(
    args: args,
    getPriceOnDateUseCase: ref.watch(getPriceOnDateUseCaseProvider),
    getCurrentPriceUseCase: ref.watch(getCurrentPriceUseCaseProvider),
  ),
);
