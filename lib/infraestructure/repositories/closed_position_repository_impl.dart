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

/// Cuánto se vende de un lote.
class _LotSale {
  const _LotSale(this.lot, this.quantity);

  final Position lot;
  final double quantity;

  bool get sellsWholeLot => (lot.quantity - quantity).abs() <= _quantityEpsilon;
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

      // `await`: sin él, un error de Supabase dentro del cierre se escapaba
      // del catch como excepción en vez de volver como Left.
      if (Uuid.isValidUUID(fromString: positionId)) {
        return await _closeSingleLot(
          positionId: positionId,
          quantity: quantity,
          closePrice: closePrice,
          closeDate: closeDate,
        );
      }

      return await _closeByTicker(
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

    if (position.isReadOnly) return Left(readOnlyPositionError());

    if (quantity > position.quantity + _quantityEpsilon) {
      return Left(
        HttpError(
          code: 'invalid_close_quantity',
          message: 'No podés vender más acciones de las que tenés',
        ),
      );
    }

    return _close(
      ticker: position.ticker,
      lots: [position],
      quantity: quantity,
      closePrice: closePrice,
      closeDate: closeDate,
    );
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
        // Solo las compras manuales: las importadas de eToro se cierran en
        // eToro y llegan solas al historial.
        .where(
          (position) =>
              !position.isReadOnly &&
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

    return _close(
      ticker: normalizedTicker,
      lots: lots,
      quantity: quantity,
      closePrice: closePrice,
      closeDate: closeDate,
    );
  }

  /// Vende [quantity] de [lots] (ya ordenados por fecha: FIFO). El orden
  /// importa para no perder datos: primero se calcula qué se vende de cada
  /// lote (sin tocar nada), después se guarda la venta y recién entonces se
  /// borran o achican los lotes. Si eso falla, se deshace la venta. Antes se
  /// borraban los lotes primero: si después fallaba el guardado, la posición
  /// desaparecía sin quedar registrada la venta (bug 2026-10-06).
  Future<Either<HttpError, ClosedPosition>> _close({
    required String ticker,
    required List<Position> lots,
    required double quantity,
    required double closePrice,
    required DateTime closeDate,
  }) async {
    final sales = <_LotSale>[];
    var remaining = quantity;
    for (final lot in lots) {
      if (remaining <= _quantityEpsilon) break;
      final sell = remaining < lot.quantity ? remaining : lot.quantity;
      sales.add(_LotSale(lot, sell));
      remaining -= sell;
    }
    if (remaining > _quantityEpsilon) {
      return Left(
        HttpError(
          code: 'invalid_close_quantity',
          message: 'No podés vender más acciones de las que tenés',
        ),
      );
    }

    final costBasisSold = sales.fold<double>(
      0,
      (sum, s) => sum + s.quantity * s.lot.purchasePrice,
    );
    final closed = ClosedPosition(
      id: _uuid.v4(),
      ticker: ticker,
      quantity: quantity,
      avgPurchasePrice: costBasisSold / quantity,
      closePrice: closePrice,
      closeDate: closeDate,
      closedAt: DateTime.now(),
    );
    await remoteDataSource.save(closed);

    for (final sale in sales) {
      final result =
          sale.sellsWholeLot
              ? await positionRepository.deletePosition(sale.lot.id)
              : await positionRepository.updatePositionQuantity(
                id: sale.lot.id,
                quantity: sale.lot.quantity - sale.quantity,
              );
      final error = result.fold((error) => error, (_) => null);
      if (error != null) {
        // Sin los lotes ajustados, la venta no puede quedar registrada.
        try {
          await remoteDataSource.delete(closed.id);
        } catch (_) {}
        return Left(error);
      }
    }
    return Right(closed);
  }
}

final closedPositionRepositoryProvider = Provider<ClosedPositionRepository>(
  (ref) => ClosedPositionRepositoryImpl(
    remoteDataSource: ref.watch(closedPositionRemoteDataSourceProvider),
    positionRepository: ref.watch(positionRepositoryProvider),
  ),
);
