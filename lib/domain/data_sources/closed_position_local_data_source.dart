import 'package:portfolio_assistant/domain/entities/closed_position.dart';

abstract class ClosedPositionLocalDataSource {
  Future<List<ClosedPosition>> getAll();

  Future<void> save(ClosedPosition position);
}
