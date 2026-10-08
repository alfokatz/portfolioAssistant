import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';

/// Lo que la pantalla de origen ya sabe de una posición: el resumen
/// agregado y cada compra, con el precio que tenía cargado. Con esto el
/// detalle se pinta completo en el primer frame y después refresca en el
/// lugar.
class PositionDetailSeed {
  const PositionDetailSeed({required this.summary, required this.lots});

  final PositionValuation summary;

  /// Más reciente primero, igual que los devuelve el use case.
  final List<PositionValuation> lots;

  /// `null` si no hay compras de ese ticker.
  static PositionDetailSeed? fromLots(List<PositionValuation> lots) {
    if (lots.isEmpty) return null;
    final sorted = [...lots]
      ..sort((a, b) => b.position.purchaseDate.compareTo(a.position.purchaseDate));
    final aggregated = PortfolioCalculator.aggregateByTicker(sorted);
    if (aggregated.isEmpty) return null;
    return PositionDetailSeed(summary: aggregated.first, lots: sorted);
  }
}

/// Parámetro del provider del detalle. La identidad es solo el ticker: el
/// seed solo define el estado inicial, no otra instancia del provider.
class PositionDetailArgs {
  const PositionDetailArgs(this.ticker, {this.seed});

  final String ticker;
  final PositionDetailSeed? seed;

  @override
  bool operator ==(Object other) =>
      other is PositionDetailArgs && other.ticker == ticker;

  @override
  int get hashCode => ticker.hashCode;
}

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

  /// Código del error de carga (`position_not_found` si ya no hay compras
  /// de ese ticker: se vendió o se borró).
  final String? errorCode;
  final PositionValuation? summary;
  final PositionDetailCloseRequest? closeRequest;
  final bool shouldPop;

  const PositionDetailState({
    this.lots = const [],
    this.isLoading = true,
    this.errorMessage,
    this.errorCode,
    this.summary,
    this.closeRequest,
    this.shouldPop = false,
  });

  /// La posición ya no está en la cartera.
  bool get notFound => errorCode == 'position_not_found';

  PositionDetailState copyWith({
    List<PositionValuation>? lots,
    bool? isLoading,
    String? errorMessage,
    String? errorCode,
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
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      summary: clearSummary ? null : (summary ?? this.summary),
      closeRequest:
          clearCloseRequest ? null : (closeRequest ?? this.closeRequest),
      shouldPop: shouldPop ?? this.shouldPop,
    );
  }
}
