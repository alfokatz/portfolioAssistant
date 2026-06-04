import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/data_sources/closed_position_local_data_source.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/repositories/closed_position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/closed_position_local_data_source_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/position_repository_impl.dart';
import 'package:uuid/uuid.dart';

const _quantityEpsilon = 1e-6;

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
    required String positionId,
    required double quantity,
    required double closePrice,
    required DateTime closeDate,
  }) async {
    try {
      if (quantity <= 0 || closePrice <= 0) {
        return Left(
          HttpError(
            code: 'invalid_close',
            message: 'Cantidad y precio de cierre deben ser mayores a cero',
          ),
        );
      }

      final positionResult =
          await positionRepository.getPositionById(positionId);
      final position = positionResult.fold(
        (error) => null,
        (value) => value,
      );
      if (positionResult.isLeft() || position == null) {
        return positionResult.fold(
          Left.new,
          (_) => Left(
            HttpError(
              code: 'position_not_found',
              message: 'Posición no encontrada',
            ),
          ),
        );
      }

      if (quantity > position.quantity + _quantityEpsilon) {
        return Left(
          HttpError(
            code: 'invalid_close_quantity',
            message: 'No podés vender más acciones de las que tenés',
          ),
        );
      }

      final closesEntireLot =
          (position.quantity - quantity).abs() <= _quantityEpsilon;

      if (closesEntireLot) {
        final deleteResult = await positionRepository.deletePosition(positionId);
        final deleteError = deleteResult.fold((error) => error, (_) => null);
        if (deleteError != null) return Left(deleteError);
      } else {
        final remaining = position.quantity - quantity;
        final updateResult = await positionRepository.updatePositionQuantity(
          id: positionId,
          quantity: remaining,
        );
        final updateError = updateResult.fold((error) => error, (_) => null);
        if (updateError != null) return Left(updateError);
      }

      final closed = ClosedPosition(
        id: _uuid.v4(),
        ticker: position.ticker,
        quantity: quantity,
        avgPurchasePrice: position.purchasePrice,
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
