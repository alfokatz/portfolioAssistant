enum BuyInputMode { shares, usd }

class AddPositionArgs {
  const AddPositionArgs({
    this.prefilledTicker,
    this.prefilledQuantity,
    this.prefilledPrice,
  });

  final String? prefilledTicker;
  final double? prefilledQuantity;
  final double? prefilledPrice;
}

class AddPositionState {
  final DateTime purchaseDate;
  final bool saving;
  final bool loadingPrice;
  final bool datePicked;
  final BuyInputMode mode;
  final double? currentPrice;
  final bool loadingCurrent;
  final String tickerText;
  final String quantityText;
  final String priceText;

  const AddPositionState({
    required this.purchaseDate,
    this.saving = false,
    this.loadingPrice = false,
    this.datePicked = false,
    this.mode = BuyInputMode.shares,
    this.currentPrice,
    this.loadingCurrent = false,
    this.tickerText = '',
    this.quantityText = '',
    this.priceText = '',
  });

  AddPositionState copyWith({
    DateTime? purchaseDate,
    bool? saving,
    bool? loadingPrice,
    bool? datePicked,
    BuyInputMode? mode,
    double? currentPrice,
    bool? loadingCurrent,
    String? tickerText,
    String? quantityText,
    String? priceText,
    bool clearCurrentPrice = false,
  }) {
    return AddPositionState(
      purchaseDate: purchaseDate ?? this.purchaseDate,
      saving: saving ?? this.saving,
      loadingPrice: loadingPrice ?? this.loadingPrice,
      datePicked: datePicked ?? this.datePicked,
      mode: mode ?? this.mode,
      currentPrice:
          clearCurrentPrice ? null : (currentPrice ?? this.currentPrice),
      loadingCurrent: loadingCurrent ?? this.loadingCurrent,
      tickerText: tickerText ?? this.tickerText,
      quantityText: quantityText ?? this.quantityText,
      priceText: priceText ?? this.priceText,
    );
  }
}
