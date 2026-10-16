/// De dónde viene una posición.
enum PositionSource {
  /// Cargada a mano en Porty: se edita y se cierra desde la app.
  manual,

  /// Importada de eToro: de solo lectura en Porty, se actualiza sola.
  etoro,

  /// Importada de Binance (saldo de cripto): de solo lectura, se actualiza
  /// sola.
  binance,

  /// Solo en una posición agregada por ticker (ver
  /// `PortfolioCalculator.aggregateByTicker`) cuando hay compras manuales e
  /// importadas de eToro.
  mixed,

  /// Como [mixed], con lo importado de Binance.
  mixedBinance;

  static PositionSource fromWire(String? value) => switch (value) {
    'etoro' => PositionSource.etoro,
    'binance' => PositionSource.binance,
    _ => PositionSource.manual,
  };

  /// Tiene algo importado (no se puede editar, cerrar ni borrar entero).
  bool get hasImported => this != PositionSource.manual;

  /// Lo importado viene de Binance (para la marca y los textos).
  bool get isBinance =>
      this == PositionSource.binance || this == PositionSource.mixedBinance;

  /// La agregada de varias compras: si todas tienen el mismo origen, ese;
  /// si no, la mezcla con el bróker que aparezca.
  static PositionSource combine(Set<PositionSource> sources) {
    if (sources.length == 1) return sources.first;
    return sources.contains(PositionSource.binance) &&
            !sources.contains(PositionSource.etoro)
        ? PositionSource.mixedBinance
        : PositionSource.mixed;
  }
}

class Position {
  final String id;
  final String ticker;
  final double quantity;
  final double purchasePrice;
  final DateTime purchaseDate;
  final PositionSource source;

  /// Última vez que eToro confirmó esta posición. `null` en las manuales.
  final DateTime? syncedAt;

  /// Precio que informó eToro en [syncedAt]. Solo es respaldo: se usa si
  /// Porty no consigue cotización propia (antes se valuaba al precio de
  /// compra y el P&L daba 0). `null` en las manuales.
  final double? brokerPrice;

  const Position({
    required this.id,
    required this.ticker,
    required this.quantity,
    required this.purchasePrice,
    required this.purchaseDate,
    this.source = PositionSource.manual,
    this.syncedAt,
    this.brokerPrice,
  });

  double get costBasis => quantity * purchasePrice;

  /// Importada de un bróker: Porty no la edita ni la cierra.
  bool get isReadOnly => source.hasImported;

  Position copyWith({
    String? id,
    String? ticker,
    double? quantity,
    double? purchasePrice,
    DateTime? purchaseDate,
    PositionSource? source,
    DateTime? syncedAt,
    double? brokerPrice,
  }) {
    return Position(
      id: id ?? this.id,
      ticker: ticker ?? this.ticker,
      quantity: quantity ?? this.quantity,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      source: source ?? this.source,
      syncedAt: syncedAt ?? this.syncedAt,
      brokerPrice: brokerPrice ?? this.brokerPrice,
    );
  }
}
