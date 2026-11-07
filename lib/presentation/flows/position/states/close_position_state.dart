enum CloseScope { all, partial }

enum SellInputMode { shares, usd }

class ClosePositionArgs {
  const ClosePositionArgs({
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

class ClosePositionState {
  final DateTime closeDate;
  final bool saving;
  final bool loadingPrice;
  final CloseScope scope;
  final SellInputMode sellMode;
  final String priceText;
  final String sellAmountText;

  const ClosePositionState({
    required this.closeDate,
    this.saving = false,
    this.loadingPrice = false,
    this.scope = CloseScope.all,
    this.sellMode = SellInputMode.shares,
    this.priceText = '',
    required this.sellAmountText,
  });

  ClosePositionState copyWith({
    DateTime? closeDate,
    bool? saving,
    bool? loadingPrice,
    CloseScope? scope,
    SellInputMode? sellMode,
    String? priceText,
    String? sellAmountText,
  }) {
    return ClosePositionState(
      closeDate: closeDate ?? this.closeDate,
      saving: saving ?? this.saving,
      loadingPrice: loadingPrice ?? this.loadingPrice,
      scope: scope ?? this.scope,
      sellMode: sellMode ?? this.sellMode,
      priceText: priceText ?? this.priceText,
      sellAmountText: sellAmountText ?? this.sellAmountText,
    );
  }
}
