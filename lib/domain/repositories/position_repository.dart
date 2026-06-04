import 'package:dartz/dartz.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';

abstract class PositionRepository {
  Future<Either<HttpError, List<Position>>> getPositions();

  Future<Either<HttpError, Position>> addPosition({
    required String ticker,
    required double quantity,
    required double purchasePrice,
    required DateTime purchaseDate,
  });

  Future<Either<HttpError, void>> deletePosition(String id);

  Future<Either<HttpError, void>> deletePositionsByTicker(String ticker);
}
