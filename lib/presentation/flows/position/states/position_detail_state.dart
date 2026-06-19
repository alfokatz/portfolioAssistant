import 'package:portfolio_assistant/domain/entities/position_valuation.dart';

class PositionDetailCloseRequest {
  const PositionDetailCloseRequest({
    required this.positionId,
    required this.ticker,
    required this.quantity,
    required this.avgPurchasePrice,
  });

  final String positionId;
  final String ticker;
  final double quantity;
  final double avgPurchasePrice;
}

class PositionDetailState {
  final List<PositionValuation> lots;
  final bool isLoading;
  final String? errorMessage;
  final PositionValuation? summary;
  final PositionDetailCloseRequest? closeRequest;
  final bool shouldPop;

  const PositionDetailState({
    this.lots = const [],
    this.isLoading = true,
    this.errorMessage,
    this.summary,
    this.closeRequest,
    this.shouldPop = false,
  });

  PositionDetailState copyWith({
    List<PositionValuation>? lots,
    bool? isLoading,
    String? errorMessage,
    PositionValuation? summary,
    PositionDetailCloseRequest? closeRequest,
    bool? shouldPop,
    bool clearError = false,
    bool clearCloseRequest = false,
    bool clearSummary = false,
  }) {
    return PositionDetailState(
      lots: lots ?? this.lots,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      summary: clearSummary ? null : (summary ?? this.summary),
      closeRequest:
          clearCloseRequest ? null : (closeRequest ?? this.closeRequest),
      shouldPop: shouldPop ?? this.shouldPop,
    );
  }
}
