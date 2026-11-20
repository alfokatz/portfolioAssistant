import 'package:hive/hive.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';

class PositionModel extends HiveObject {
  String id;
  String ticker;
  double quantity;
  double purchasePrice;
  int purchaseDateMillis;

  PositionModel({
    required this.id,
    required this.ticker,
    required this.quantity,
    required this.purchasePrice,
    required this.purchaseDateMillis,
  });

  Position toEntity() => Position(
        id: id,
        ticker: ticker,
        quantity: quantity,
        purchasePrice: purchasePrice,
        purchaseDate:
            DateTime.fromMillisecondsSinceEpoch(purchaseDateMillis),
      );

  static PositionModel fromEntity(Position position) => PositionModel(
        id: position.id,
        ticker: position.ticker,
        quantity: position.quantity,
        purchasePrice: position.purchasePrice,
        purchaseDateMillis: position.purchaseDate.millisecondsSinceEpoch,
      );
}

class PositionModelAdapter extends TypeAdapter<PositionModel> {
  @override
  final int typeId = 0;

  @override
  PositionModel read(BinaryReader reader) {
    return PositionModel(
      id: reader.readString(),
      ticker: reader.readString(),
      quantity: reader.readDouble(),
      purchasePrice: reader.readDouble(),
      purchaseDateMillis: reader.readInt(),
    );
  }

  @override
  void write(BinaryWriter writer, PositionModel obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.ticker)
      ..writeDouble(obj.quantity)
      ..writeDouble(obj.purchasePrice)
      ..writeInt(obj.purchaseDateMillis);
  }
}
