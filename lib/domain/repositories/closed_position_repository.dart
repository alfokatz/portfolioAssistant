import 'package:dartz/dartz.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';

abstract class ClosedPositionRepository {
  Future<Either<HttpError, List<ClosedPosition>>> getClosedPositions();

  Future<Either<HttpError, ClosedPosition>> closePosition({
    required String ticker,
    required double quantity,
    required double avgPurchasePrice,
    required double closePrice,
    required DateTime closeDate,
  });
}
