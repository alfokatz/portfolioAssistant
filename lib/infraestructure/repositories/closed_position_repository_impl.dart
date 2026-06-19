import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/config/supabase/supabase_error_mapper.dart';
import 'package:portfolio_assistant/domain/data_sources/closed_position_remote_data_source.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/repositories/closed_position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/supabase/closed_position_supabase_data_source.dart';
import 'package:portfolio_assistant/infraestructure/repositories/position_repository_impl.dart';
import 'package:uuid/uuid.dart';

const _quantityEpsilon = 1e-6;

class _FifoCloseResult {
  const _FifoCloseResult({
    required this.avgPurchasePrice,
    required this.sourcePositionId,
  });

  final double avgPurchasePrice;
  final String? sourcePositionId;
}

class ClosedPositionRepositoryImpl implements ClosedPositionRepository {
  final ClosedPositionRemoteDataSource remoteDataSource;
  final PositionRepository positionRepository;
  final Uuid _uuid;

  ClosedPositionRepositoryImpl({
    required this.remoteDataSource,
    required this.positionRepository,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  @override
  Future<Either<HttpError, List<ClosedPosition>>> getClosedPositions() async {
    try {
      final positions = await remoteDataSource.getAll();
      return Right(positions);
    } catch (e) {
      return Left(SupabaseErrorMapper.fromObject(e));
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
      final validationError = _validateCloseInputs(
        quantity: quantity,
        closePrice: closePrice,
      );
      if (validationError != null) return Left(validationError);

      if (Uuid.isValidUUID(fromString: positionId)) {
        return _closeSingleLot(
          positionId: positionId,
          quantity: quantity,
          closePrice: closePrice,
          closeDate: closeDate,
        );
      }

      return _closeByTicker(
        ticker: positionId,
        quantity: quantity,
        closePrice: closePrice,
        closeDate: closeDate,
      );
    } catch (e) {
      return Left(SupabaseErrorMapper.fromObject(e));
    }
  }

  HttpError? _validateCloseInputs({
    required double quantity,
    required double closePrice,
  }) {
    if (quantity <= 0 || closePrice <= 0) {
      return HttpError(
        code: 'invalid_close',
        message: 'Cantidad y precio de cierre deben ser mayores a cero',
      );
    }
    return null;
  }

  Future<Either<HttpError, ClosedPosition>> _closeSingleLot({
    required String positionId,
    required double quantity,
    required double closePrice,
    required DateTime closeDate,
  }) async {
    final positionResult = await positionRepository.getPositionById(positionId);
    final position = positionResult.fold((error) => null, (value) => value);
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

    final fifoResult = await _applyFifoClose(
      lots: [position],
      quantity: quantity,
    );
    final fifoError = fifoResult.fold((error) => error, (_) => null);
    if (fifoError != null) return Left(fifoError);

    final closeMeta = fifoResult.getOrElse(
      () => throw StateError('FIFO close result missing'),
    );

    final closed = ClosedPosition(
      id: _uuid.v4(),
      ticker: position.ticker,
      quantity: quantity,
      avgPurchasePrice: closeMeta.avgPurchasePrice,
      closePrice: closePrice,
      closeDate: closeDate,
      closedAt: DateTime.now(),
    );
    await remoteDataSource.save(
      closed,
      sourcePositionId: closeMeta.sourcePositionId,
    );
    return Right(closed);
  }

  Future<Either<HttpError, ClosedPosition>> _closeByTicker({
    required String ticker,
    required double quantity,
    required double closePrice,
    required DateTime closeDate,
  }) async {
    final positionsResult = await positionRepository.getPositions();
    if (positionsResult.isLeft()) {
      return Left(
        positionsResult.fold((error) => error, (_) => throw StateError('unreachable')),
      );
    }

    final normalizedTicker = PortfolioCalculator.normalizeTicker(ticker);
    final lots = positionsResult
        .getOrElse(() => throw StateError('positions missing'))
        .where(
          (position) =>
              PortfolioCalculator.normalizeTicker(position.ticker) ==
              normalizedTicker,
        )
        .toList()
      ..sort((a, b) => a.purchaseDate.compareTo(b.purchaseDate));

    if (lots.isEmpty) {
      return Left(
        HttpError(
          code: 'position_not_found',
          message: 'Posición no encontrada',
        ),
      );
    }

    final totalQuantity = lots.fold<double>(
      0,
      (sum, lot) => sum + lot.quantity,
    );
    if (quantity > totalQuantity + _quantityEpsilon) {
      return Left(
        HttpError(
          code: 'invalid_close_quantity',
          message: 'No podés vender más acciones de las que tenés',
        ),
      );
    }

    final fifoResult = await _applyFifoClose(lots: lots, quantity: quantity);
    final fifoError = fifoResult.fold((error) => error, (_) => null);
    if (fifoError != null) return Left(fifoError);

    final closeMeta = fifoResult.getOrElse(
      () => throw StateError('FIFO close result missing'),
    );

    final closed = ClosedPosition(
      id: _uuid.v4(),
      ticker: normalizedTicker,
      quantity: quantity,
      avgPurchasePrice: closeMeta.avgPurchasePrice,
      closePrice: closePrice,
      closeDate: closeDate,
      closedAt: DateTime.now(),
    );
    await remoteDataSource.save(
      closed,
      sourcePositionId: closeMeta.sourcePositionId,
    );
    return Right(closed);
  }

  Future<Either<HttpError, _FifoCloseResult>> _applyFifoClose({
    required List<Position> lots,
    required double quantity,
  }) async {
    var remaining = quantity;
    var costBasisSold = 0.0;
    String? sourcePositionId;
    var lotsTouched = 0;

    for (final lot in lots) {
      if (remaining <= _quantityEpsilon) break;

      final sellFromLot = remaining < lot.quantity ? remaining : lot.quantity;
      costBasisSold += sellFromLot * lot.purchasePrice;
      remaining -= sellFromLot;
      lotsTouched++;

      if ((lot.quantity - sellFromLot).abs() <= _quantityEpsilon) {
        final deleteResult = await positionRepository.deletePosition(lot.id);
        final deleteError = deleteResult.fold((error) => error, (_) => null);
        if (deleteError != null) return Left(deleteError);
      } else {
        final updateResult = await positionRepository.updatePositionQuantity(
          id: lot.id,
          quantity: lot.quantity - sellFromLot,
        );
        final updateError = updateResult.fold((error) => error, (_) => null);
        if (updateError != null) return Left(updateError);
      }

      sourcePositionId ??= lot.id;
      if (lotsTouched > 1) {
        sourcePositionId = null;
      }
    }

    if (remaining > _quantityEpsilon) {
      return Left(
        HttpError(
          code: 'invalid_close_quantity',
          message: 'No podés vender más acciones de las que tenés',
        ),
      );
    }

    return Right(
      _FifoCloseResult(
        avgPurchasePrice: costBasisSold / quantity,
        sourcePositionId: sourcePositionId,
      ),
    );
  }
}

final closedPositionRepositoryProvider = Provider<ClosedPositionRepository>(
  (ref) => ClosedPositionRepositoryImpl(
    remoteDataSource: ref.watch(closedPositionRemoteDataSourceProvider),
    positionRepository: ref.watch(positionRepositoryProvider),
  ),
);
