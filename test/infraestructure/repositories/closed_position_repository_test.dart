import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/data_sources/closed_position_remote_data_source.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/closed_position_repository_impl.dart';

/// Registro común de lo que pasa, en orden.
final _log = <String>[];

class _Closed implements ClosedPositionRemoteDataSource {
  final saved = <ClosedPosition>[];
  Object? saveError;

  @override
  Future<List<ClosedPosition>> getAll() async => saved;

  @override
  Future<void> save(ClosedPosition position) async {
    if (saveError != null) throw saveError!;
    _log.add('save');
    saved.add(position);
  }

  @override
  Future<void> delete(String id) async {
    _log.add('undo');
    saved.removeWhere((p) => p.id == id);
  }
}

class _Positions implements PositionRepository {
  _Positions(this.lots);
  final List<Position> lots;
  HttpError? deleteError;

  @override
  Future<Either<HttpError, List<Position>>> getPositions() async =>
      Right(List.of(lots));

  @override
  Future<Either<HttpError, Position>> getPositionById(String id) async =>
      Right(lots.firstWhere((l) => l.id == id));

  @override
  Future<Either<HttpError, void>> deletePosition(String id) async {
    if (deleteError != null) return Left(deleteError!);
    _log.add('delete $id');
    lots.removeWhere((l) => l.id == id);
    return const Right(null);
  }

  @override
  Future<Either<HttpError, Position>> updatePositionQuantity({
    required String id,
    required double quantity,
  }) async {
    _log.add('update $id $quantity');
    final i = lots.indexWhere((l) => l.id == id);
    lots[i] = lots[i].copyWith(quantity: quantity);
    return Right(lots[i]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _lotA = '11111111-1111-4111-8111-111111111111';
const _lotB = '22222222-2222-4222-8222-222222222222';

Position _lot(String id, double qty, double price, int month) => Position(
  id: id,
  ticker: 'VOO',
  quantity: qty,
  purchasePrice: price,
  purchaseDate: DateTime(2024, month, 1),
);

void main() {
  setUp(_log.clear);

  ClosedPositionRepositoryImpl repo(_Closed closed, _Positions positions) =>
      ClosedPositionRepositoryImpl(
        remoteDataSource: closed,
        positionRepository: positions,
      );

  test('selling a whole lot: the sale is saved first, then the lot is '
      'deleted (bug 2026-10-06: the lot was deleted first and the sale '
      'pointed at it)', () async {
    final closed = _Closed();
    final positions = _Positions([_lot(_lotA, 1, 509.84, 7)]);
    final result = await repo(closed, positions).closePosition(
      positionId: _lotA,
      quantity: 1,
      closePrice: 716.85,
      closeDate: DateTime(2026, 10, 6),
    );
    expect(result.isRight(), isTrue);
    expect(_log, ['save', 'delete $_lotA']);
    expect(closed.saved.single.avgPurchasePrice, 509.84);
    expect(positions.lots, isEmpty);
  });

  test('part of a lot: the lot is reduced, not deleted', () async {
    final positions = _Positions([_lot(_lotA, 2, 100, 1)]);
    await repo(_Closed(), positions).closePosition(
      positionId: _lotA,
      quantity: 0.5,
      closePrice: 150,
      closeDate: DateTime(2026, 10, 6),
    );
    expect(_log, ['save', 'update $_lotA 1.5']);
  });

  test('by ticker, oldest lot first (FIFO), with the average cost of what '
      'was sold', () async {
    final closed = _Closed();
    final positions = _Positions([
      _lot(_lotB, 1, 200, 6),
      _lot(_lotA, 1, 100, 1),
    ]);
    await repo(closed, positions).closePosition(
      positionId: 'VOO',
      quantity: 1.5,
      closePrice: 300,
      closeDate: DateTime(2026, 10, 6),
    );
    expect(_log, ['save', 'delete $_lotA', 'update $_lotB 0.5']);
    expect(closed.saved.single.avgPurchasePrice, closeTo(400 / 3, 1e-9));
  });

  test('if the lots cannot be adjusted, the sale is undone', () async {
    final closed = _Closed();
    final positions = _Positions([_lot(_lotA, 1, 100, 1)])
      ..deleteError = HttpError(code: 'x', message: 'no se pudo');
    final result = await repo(closed, positions).closePosition(
      positionId: _lotA,
      quantity: 1,
      closePrice: 150,
      closeDate: DateTime(2026, 10, 6),
    );
    expect(result.isLeft(), isTrue);
    expect(_log, ['save', 'undo']);
    expect(closed.saved, isEmpty);
    expect(positions.lots, hasLength(1), reason: 'la posición sigue');
  });

  test('a database error saving the sale comes back as an error (not an '
      'exception), and the position is untouched', () async {
    final positions = _Positions([_lot(_lotA, 1, 100, 1)]);
    final closed = _Closed()..saveError = Exception('23503');
    final result = await repo(closed, positions).closePosition(
      positionId: _lotA,
      quantity: 1,
      closePrice: 150,
      closeDate: DateTime(2026, 10, 6),
    );
    expect(result.isLeft(), isTrue);
    expect(_log, isEmpty);
    expect(positions.lots, hasLength(1));
  });

  test('selling more than you have is rejected without touching anything', () async {
    final positions = _Positions([_lot(_lotA, 1, 100, 1)]);
    final result = await repo(_Closed(), positions).closePosition(
      positionId: 'VOO',
      quantity: 2,
      closePrice: 150,
      closeDate: DateTime(2026, 10, 6),
    );
    expect(result.isLeft(), isTrue);
    expect(_log, isEmpty);
  });
}
