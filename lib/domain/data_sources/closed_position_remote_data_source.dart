import 'package:portfolio_assistant/domain/entities/closed_position.dart';

abstract class ClosedPositionRemoteDataSource {
  Future<List<ClosedPosition>> getAll();

  Future<void> save(
    ClosedPosition position, {
    String? sourcePositionId,
  });
}
