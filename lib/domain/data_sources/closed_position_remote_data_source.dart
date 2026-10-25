import 'package:portfolio_assistant/domain/entities/closed_position.dart';

abstract class ClosedPositionRemoteDataSource {
  Future<List<ClosedPosition>> getAll();

  Future<void> save(ClosedPosition position);

  /// Deshace un [save] (si después no se pudieron ajustar los lotes).
  Future<void> delete(String id);
}
