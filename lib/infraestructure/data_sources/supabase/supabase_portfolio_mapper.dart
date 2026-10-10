import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';

class SupabasePortfolioMapper {
  SupabasePortfolioMapper._();

  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.parse(value.toString());
  }

  static Position positionFromRow(Map<String, dynamic> row) {
    return Position(
      id: row['id'] as String,
      ticker: row['ticker'] as String,
      quantity: _toDouble(row['quantity']),
      purchasePrice: _toDouble(row['purchase_price']),
      purchaseDate: DateTime.parse(row['purchase_date'] as String).toLocal(),
      source: PositionSource.fromWire(row['source'] as String?),
      syncedAt: _optionalDate(row['synced_at']),
      brokerPrice: _optionalDouble(row['broker_price']),
    );
  }

  static DateTime? _optionalDate(Object? value) =>
      value is String ? DateTime.parse(value).toLocal() : null;

  static double? _optionalDouble(Object? value) =>
      value == null ? null : _toDouble(value);

  /// Sin `source` ni `broker_price`: la base pone 'manual' al insertar y no
  /// lo cambia al actualizar. Las filas de eToro solo las escribe la edge
  /// function.
  static Map<String, dynamic> positionToRow({
    required Position position,
    required String userId,
  }) {
    return {
      'id': position.id,
      'user_id': userId,
      'ticker': position.ticker,
      'quantity': position.quantity,
      'purchase_price': position.purchasePrice,
      'purchase_date': position.purchaseDate.toUtc().toIso8601String(),
    };
  }

  static ClosedPosition closedPositionFromRow(Map<String, dynamic> row) {
    return ClosedPosition(
      id: row['id'] as String,
      ticker: row['ticker'] as String,
      quantity: _toDouble(row['quantity']),
      avgPurchasePrice: _toDouble(row['avg_purchase_price']),
      closePrice: _toDouble(row['close_price']),
      closeDate: DateTime.parse(row['close_date'] as String).toLocal(),
      closedAt: DateTime.parse(row['closed_at'] as String).toLocal(),
      source: PositionSource.fromWire(row['source'] as String?),
      realizedPnl: _optionalDouble(row['realized_pnl']),
    );
  }

  static Map<String, dynamic> closedPositionToRow({
    required ClosedPosition position,
    required String userId,
  }) {
    // Sin `source_position_id`: apuntaba al lote vendido, que al venderse
    // entero se borra, y la clave foránea rechazaba la venta (bug
    // 2026-10-06). Nadie lo leía.
    return {
      'id': position.id,
      'user_id': userId,
      'ticker': position.ticker,
      'quantity': position.quantity,
      'avg_purchase_price': position.avgPurchasePrice,
      'close_price': position.closePrice,
      'close_date': position.closeDate.toUtc().toIso8601String(),
      'closed_at': position.closedAt.toUtc().toIso8601String(),
    };
  }
}
