import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/data_sources/position_local_data_source.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/position_local_data_source_impl.dart';
import 'package:uuid/uuid.dart';

class PositionRepositoryImpl implements PositionRepository {
  final PositionLocalDataSource localDataSource;
  final Uuid _uuid;

  PositionRepositoryImpl({
    required this.localDataSource,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  @override
  Future<Either<HttpError, Position>> addPosition({
    required String ticker,
    required double quantity,
    required double purchasePrice,
    required DateTime purchaseDate,
  }) async {
    try {
      final normalized = PortfolioCalculator.normalizeTicker(ticker);
      if (normalized.isEmpty) {
        return Left(
          HttpError(
            code: 'invalid_ticker',
            message: 'Ticker inválido',
          ),
        );
      }
      if (quantity <= 0 || purchasePrice <= 0) {
        return Left(
          HttpError(
            code: 'invalid_position',
            message: 'Cantidad y precio deben ser mayores a cero',
          ),
        );
      }

      final position = Position(
        id: _uuid.v4(),
        ticker: normalized,
        quantity: quantity,
        purchasePrice: purchasePrice,
        purchaseDate: purchaseDate,
      );
      await localDataSource.save(position);
      return Right(position);
    } catch (e) {
      return Left(
        HttpError(code: 'position_error', message: e.toString()),
      );
    }
  }

  @override
  Future<Either<HttpError, void>> deletePosition(String id) async {
    try {
      await localDataSource.delete(id);
      return const Right(null);
    } catch (e) {
      return Left(
        HttpError(code: 'position_error', message: e.toString()),
      );
    }
  }

  @override
  Future<Either<HttpError, void>> deletePositionsByTicker(String ticker) async {
    try {
      final normalized = PortfolioCalculator.normalizeTicker(ticker);
      final positions = await localDataSource.getAll();
      for (final position in positions) {
        if (PortfolioCalculator.normalizeTicker(position.ticker) == normalized) {
          await localDataSource.delete(position.id);
        }
      }
      return const Right(null);
    } catch (e) {
      return Left(
        HttpError(code: 'position_error', message: e.toString()),
      );
    }
  }

  @override
  Future<Either<HttpError, Position>> getPositionById(String id) async {
    try {
      final position = await localDataSource.getById(id);
      if (position == null) {
        return Left(
          HttpError(code: 'position_not_found', message: 'Posición no encontrada'),
        );
      }
      return Right(position);
    } catch (e) {
      return Left(
        HttpError(code: 'position_error', message: e.toString()),
      );
    }
  }

  @override
  Future<Either<HttpError, Position>> updatePositionQuantity({
    required String id,
    required double quantity,
  }) async {
    try {
      if (quantity <= 0) {
        return Left(
          HttpError(
            code: 'invalid_position',
            message: 'La cantidad debe ser mayor a cero',
          ),
        );
      }
      final existing = await localDataSource.getById(id);
      if (existing == null) {
        return Left(
          HttpError(code: 'position_not_found', message: 'Posición no encontrada'),
        );
      }
      final updated = existing.copyWith(quantity: quantity);
      await localDataSource.save(updated);
      return Right(updated);
    } catch (e) {
      return Left(
        HttpError(code: 'position_error', message: e.toString()),
      );
    }
  }

  @override
  Future<Either<HttpError, List<Position>>> getPositions() async {
    try {
      final positions = await localDataSource.getAll();
      return Right(positions);
    } catch (e) {
      return Left(
        HttpError(code: 'position_error', message: e.toString()),
      );
    }
  }
}

final positionRepositoryProvider = Provider<PositionRepository>(
  (ref) => PositionRepositoryImpl(
    localDataSource: ref.watch(positionLocalDataSourceProvider),
  ),
);
