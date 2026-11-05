import 'package:portfolio_assistant/domain/entities/price_candle.dart';

/// Un ticker que el usuario sigue sin tenerlo.
class WatchlistItem {
  const WatchlistItem({
    required this.id,
    required this.symbol,
    required this.createdAt,
    this.addedPrice,
    this.notify = true,
  });

  final String id;
  final String symbol;

  /// Precio cuando lo agregó (`null` si no había cotización).
  final double? addedPrice;

  /// Avisar si se mueve fuerte en el día.
  final bool notify;
  final DateTime createdAt;

  static WatchlistItem? fromRow(Map<String, dynamic> row) {
    final id = row['id'];
    final symbol = row['symbol'];
    final created = row['created_at'];
    if (id is! String || symbol is! String) return null;
    final price = row['added_price'];
    return WatchlistItem(
      id: id,
      symbol: symbol,
      addedPrice:
          price is num ? price.toDouble() : num.tryParse('$price')?.toDouble(),
      notify: row['notify'] as bool? ?? true,
      createdAt:
          created is String
              ? DateTime.parse(created).toLocal()
              : DateTime.now(),
    );
  }

  WatchlistItem copyWith({bool? notify}) => WatchlistItem(
    id: id,
    symbol: symbol,
    addedPrice: addedPrice,
    notify: notify ?? this.notify,
    createdAt: createdAt,
  );
}

/// Cotización para la lista: precio de hoy y variación del día.
class WatchQuote {
  const WatchQuote({required this.price, this.previousClose});

  final double price;
  final double? previousClose;

  double? get dayChangePct =>
      previousClose == null || previousClose! <= 0
          ? null
          : (price - previousClose!) / previousClose! * 100;

  /// Variación desde [addedPrice] (el precio cuando lo agregó).
  double? sinceAddedPct(double? addedPrice) =>
      addedPrice == null || addedPrice <= 0
          ? null
          : (price - addedPrice) / addedPrice * 100;

  /// El cierre anterior a [today] en [candles] (cualquier orden).
  static double? previousCloseFrom(List<PriceCandle> candles, DateTime today) {
    final day = DateTime(today.year, today.month, today.day);
    PriceCandle? best;
    for (final c in candles) {
      final d = DateTime(c.date.year, c.date.month, c.date.day);
      if (!d.isBefore(day) || c.close <= 0) continue;
      if (best == null || c.date.isAfter(best.date)) best = c;
    }
    return best?.close;
  }
}
