class Position {
  final String id;
  final String ticker;
  final double quantity;
  final double purchasePrice;
  final DateTime purchaseDate;

  const Position({
    required this.id,
    required this.ticker,
    required this.quantity,
    required this.purchasePrice,
    required this.purchaseDate,
  });

  double get costBasis => quantity * purchasePrice;

  Position copyWith({
    String? id,
    String? ticker,
    double? quantity,
    double? purchasePrice,
    DateTime? purchaseDate,
  }) {
    return Position(
      id: id ?? this.id,
      ticker: ticker ?? this.ticker,
      quantity: quantity ?? this.quantity,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      purchaseDate: purchaseDate ?? this.purchaseDate,
    );
  }
}
