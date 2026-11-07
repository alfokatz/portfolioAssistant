import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/data_sources/closed_position_remote_data_source.dart';
import 'package:portfolio_assistant/domain/data_sources/position_remote_data_source.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/infraestructure/repositories/closed_position_repository_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/position_repository_impl.dart';

/// Base de posiciones en memoria (la de verdad además tiene un trigger que
/// rechaza tocar filas de eToro; ver supabase/tests/etoro_sync_db_test.sql).
class _Remote implements PositionRemoteDataSource {
  _Remote(this.rows);
  final List<Position> rows;
  final calls = <String>[];

  @override
  Future<List<Position>> getAll() async => List.of(rows);

  @override
  Future<Position?> getById(String id) async {
    for (final r in rows) {
      if (r.id == id) return r;
    }
    return null;
  }

  @override
  Future<void> save(Position position) async {
    calls.add('save ${position.id}');
    final i = rows.indexWhere((r) => r.id == position.id);
    if (i >= 0) {
      rows[i] = position;
    } else {
      rows.add(position);
    }
  }

  @override
  Future<void> delete(String id) async {
    calls.add('delete $id');
    rows.removeWhere((r) => r.id == id);
  }

  /// Como la real: solo las manuales.
  @override
  Future<void> deleteByTicker(String ticker) async {
    calls.add('deleteByTicker $ticker');
    rows.removeWhere((r) => r.ticker == ticker && r.source == PositionSource.manual);
  }
}

class _Closed implements ClosedPositionRemoteDataSource {
  final saved = <ClosedPosition>[];

  @override
  Future<List<ClosedPosition>> getAll() async => saved;

  @override
  Future<void> save(ClosedPosition position) async => saved.add(position);

  @override
  Future<void> delete(String id) async => saved.removeWhere((p) => p.id == id);
}

const _manualId = '11111111-1111-4111-8111-111111111111';
const _etoroId = '22222222-2222-4222-8222-222222222222';

List<Position> _rows() => [
  Position(
    id: _manualId,
    ticker: 'AAPL',
    quantity: 3,
    purchasePrice: 150,
    purchaseDate: DateTime(2025, 1, 1),
  ),
  Position(
    id: _etoroId,
    ticker: 'AAPL',
    quantity: 10,
    purchasePrice: 180,
    purchaseDate: DateTime(2024, 1, 1),
    source: PositionSource.etoro,
  ),
];

String? _code<T>(Either<HttpError, T> r) => r.fold((e) => e.code, (_) => null);

void main() {
  group('posiciones de eToro: solo lectura en Porty', () {
    test('no se editan ni se borran (sin llegar a la base)', () async {
      final remote = _Remote(_rows());
      final repo = PositionRepositoryImpl(remoteDataSource: remote);

      expect(
        _code(await repo.updatePositionQuantity(id: _etoroId, quantity: 1)),
        'position_read_only',
      );
      expect(_code(await repo.deletePosition(_etoroId)), 'position_read_only');
      expect(remote.calls, isEmpty);
      expect(remote.rows.length, 2);
    });

    test('las manuales siguen igual', () async {
      final remote = _Remote(_rows());
      final repo = PositionRepositoryImpl(remoteDataSource: remote);
      expect((await repo.updatePositionQuantity(id: _manualId, quantity: 2)).isRight(), isTrue);
      expect((await repo.deletePosition(_manualId)).isRight(), isTrue);
    });

    test('borrar "todas las AAPL" (swipe, duplicados) borra solo las manuales', () async {
      final remote = _Remote(_rows());
      final repo = PositionRepositoryImpl(remoteDataSource: remote);
      await repo.deletePositionsByTicker('AAPL');
      expect(remote.rows.map((r) => r.id), [_etoroId]);
    });

    test('cerrar una compra de eToro → position_read_only, nada guardado', () async {
      final remote = _Remote(_rows());
      final closed = _Closed();
      final repo = ClosedPositionRepositoryImpl(
        remoteDataSource: closed,
        positionRepository: PositionRepositoryImpl(remoteDataSource: remote),
      );
      final result = await repo.closePosition(
        positionId: _etoroId,
        quantity: 1,
        closePrice: 200,
        closeDate: DateTime(2026, 10, 1),
      );
      expect(_code(result), 'position_read_only');
      expect(closed.saved, isEmpty);
      expect(remote.rows.firstWhere((r) => r.id == _etoroId).quantity, 10);
    });

    test('cerrar por ticker con compras mixtas: solo vende las manuales', () async {
      final remote = _Remote(_rows());
      final closed = _Closed();
      final repo = ClosedPositionRepositoryImpl(
        remoteDataSource: closed,
        positionRepository: PositionRepositoryImpl(remoteDataSource: remote),
      );
      // Hay 13 AAPL, pero solo 3 son manuales.
      final tooMany = await repo.closePosition(
        positionId: 'AAPL',
        quantity: 5,
        closePrice: 200,
        closeDate: DateTime(2026, 10, 1),
      );
      expect(_code(tooMany), 'invalid_close_quantity');

      final ok = await repo.closePosition(
        positionId: 'AAPL',
        quantity: 3,
        closePrice: 200,
        closeDate: DateTime(2026, 10, 1),
      );
      expect(ok.isRight(), isTrue);
      expect(remote.rows.map((r) => r.id), [_etoroId]);
      expect(closed.saved.single.avgPurchasePrice, 150);
    });
  });
}
