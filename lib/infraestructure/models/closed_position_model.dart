import 'package:hive/hive.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';

class ClosedPositionModel extends HiveObject {
  String id;
  String ticker;
  double quantity;
  double avgPurchasePrice;
  double closePrice;
  int closeDateMillis;
  int closedAtMillis;

  ClosedPositionModel({
    required this.id,
    required this.ticker,
    required this.quantity,
    required this.avgPurchasePrice,
    required this.closePrice,
    required this.closeDateMillis,
    required this.closedAtMillis,
  });

  ClosedPosition toEntity() => ClosedPosition(
        id: id,
        ticker: ticker,
        quantity: quantity,
        avgPurchasePrice: avgPurchasePrice,
        closePrice: closePrice,
        closeDate: DateTime.fromMillisecondsSinceEpoch(closeDateMillis),
        closedAt: DateTime.fromMillisecondsSinceEpoch(closedAtMillis),
      );

  static ClosedPositionModel fromEntity(ClosedPosition position) =>
      ClosedPositionModel(
        id: position.id,
        ticker: position.ticker,
        quantity: position.quantity,
        avgPurchasePrice: position.avgPurchasePrice,
        closePrice: position.closePrice,
        closeDateMillis: position.closeDate.millisecondsSinceEpoch,
        closedAtMillis: position.closedAt.millisecondsSinceEpoch,
      );
}

class ClosedPositionModelAdapter extends TypeAdapter<ClosedPositionModel> {
  @override
  final int typeId = 1;

  @override
  ClosedPositionModel read(BinaryReader reader) {
    return ClosedPositionModel(
      id: reader.readString(),
      ticker: reader.readString(),
      quantity: reader.readDouble(),
      avgPurchasePrice: reader.readDouble(),
      closePrice: reader.readDouble(),
      closeDateMillis: reader.readInt(),
      closedAtMillis: reader.readInt(),
    );
  }

  @override
  void write(BinaryWriter writer, ClosedPositionModel obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.ticker)
      ..writeDouble(obj.quantity)
      ..writeDouble(obj.avgPurchasePrice)
      ..writeDouble(obj.closePrice)
      ..writeInt(obj.closeDateMillis)
      ..writeInt(obj.closedAtMillis);
  }
}
