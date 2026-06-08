import 'package:portfolio_assistant/domain/entities/position.dart';

abstract class PositionRemoteDataSource {
  Future<List<Position>> getAll();

  Future<Position?> getById(String id);

  Future<void> save(Position position);

  Future<void> delete(String id);

  Future<void> deleteByTicker(String ticker);
}
