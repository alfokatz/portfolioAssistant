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
    );
  }

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
    );
  }

  static Map<String, dynamic> closedPositionToRow({
    required ClosedPosition position,
    required String userId,
    String? sourcePositionId,
  }) {
    return {
      'id': position.id,
      'user_id': userId,
      'source_position_id': sourcePositionId,
      'ticker': position.ticker,
      'quantity': position.quantity,
      'avg_purchase_price': position.avgPurchasePrice,
      'close_price': position.closePrice,
      'close_date': position.closeDate.toUtc().toIso8601String(),
      'closed_at': position.closedAt.toUtc().toIso8601String(),
    };
  }
}
