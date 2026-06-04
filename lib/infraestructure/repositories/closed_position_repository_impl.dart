import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/data_sources/closed_position_local_data_source.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/repositories/closed_position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/closed_position_local_data_source_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/position_repository_impl.dart';
import 'package:uuid/uuid.dart';

class ClosedPositionRepositoryImpl implements ClosedPositionRepository {
  final ClosedPositionLocalDataSource localDataSource;
  final PositionRepository positionRepository;
  final Uuid _uuid;

  ClosedPositionRepositoryImpl({
    required this.localDataSource,
    required this.positionRepository,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  @override
  Future<Either<HttpError, List<ClosedPosition>>> getClosedPositions() async {
    try {
      final positions = await localDataSource.getAll();
      return Right(positions);
    } catch (e) {
      return Left(
        HttpError(code: 'closed_position_error', message: e.toString()),
      );
    }
  }

  @override
  Future<Either<HttpError, ClosedPosition>> closePosition({
    required String ticker,
    required double quantity,
    required double avgPurchasePrice,
    required double closePrice,
    required DateTime closeDate,
  }) async {
    try {
      final normalized = PortfolioCalculator.normalizeTicker(ticker);
      if (normalized.isEmpty) {
        return Left(
          HttpError(code: 'invalid_ticker', message: 'Ticker inválido'),
        );
      }
      if (quantity <= 0 || avgPurchasePrice <= 0 || closePrice <= 0) {
        return Left(
          HttpError(
            code: 'invalid_close',
            message: 'Cantidad y precios deben ser mayores a cero',
          ),
        );
      }

      final deleteResult = await positionRepository.deletePositionsByTicker(
        normalized,
      );
      final deleteError = deleteResult.fold((error) => error, (_) => null);
      if (deleteError != null) return Left(deleteError);

      final closed = ClosedPosition(
        id: _uuid.v4(),
        ticker: normalized,
        quantity: quantity,
        avgPurchasePrice: avgPurchasePrice,
        closePrice: closePrice,
        closeDate: closeDate,
        closedAt: DateTime.now(),
      );
      await localDataSource.save(closed);
      return Right(closed);
    } catch (e) {
      return Left(
        HttpError(code: 'closed_position_error', message: e.toString()),
      );
    }
  }
}

final closedPositionRepositoryProvider = Provider<ClosedPositionRepository>(
  (ref) => ClosedPositionRepositoryImpl(
    localDataSource: ref.watch(closedPositionLocalDataSourceProvider),
    positionRepository: ref.watch(positionRepositoryProvider),
  ),
);
