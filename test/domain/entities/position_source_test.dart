import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/supabase/supabase_portfolio_mapper.dart';

Position _p(String id, PositionSource source, {DateTime? syncedAt}) => Position(
  id: id,
  ticker: 'AAPL',
  quantity: 1,
  purchasePrice: 100,
  purchaseDate: DateTime(2026, 1, 1),
  source: source,
  syncedAt: syncedAt,
);

void main() {
  group('origen de las posiciones', () {
    test('las manuales siguen siendo editables; las de eToro no', () {
      expect(_p('a', PositionSource.manual).isReadOnly, isFalse);
      expect(_p('b', PositionSource.etoro).isReadOnly, isTrue);
      // Una posición nueva (como las que carga la app) es manual.
      expect(
        Position(
          id: 'x',
          ticker: 'T',
          quantity: 1,
          purchasePrice: 1,
          purchaseDate: DateTime(2026),
        ).source,
        PositionSource.manual,
      );
    });

    test('agregada por ticker: mezcla de orígenes → mixed (solo lectura); '
        'la sincronización más reciente', () {
      final summary = PortfolioCalculator.summarize([
        PortfolioCalculator.valuate(position: _p('m', PositionSource.manual), currentPrice: 110),
        PortfolioCalculator.valuate(
          position: _p('e', PositionSource.etoro, syncedAt: DateTime(2026, 10, 9, 10)),
          currentPrice: 110,
        ),
      ]);
      final aapl = summary.valuations.single.position;
      expect(aapl.source, PositionSource.mixed);
      expect(aapl.isReadOnly, isTrue);
      expect(aapl.syncedAt, DateTime(2026, 10, 9, 10));
      // Los lotes conservan su origen.
      expect(summary.lots.map((l) => l.position.source), [
        PositionSource.manual,
        PositionSource.etoro,
      ]);
    });

    test('agregada de un solo origen conserva ese origen', () {
      final summary = PortfolioCalculator.summarize([
        PortfolioCalculator.valuate(position: _p('e1', PositionSource.etoro), currentPrice: 110),
        PortfolioCalculator.valuate(position: _p('e2', PositionSource.etoro), currentPrice: 110),
      ]);
      expect(summary.valuations.single.position.source, PositionSource.etoro);
    });

    test('el mapper lee source, synced_at y realized_pnl (y tolera filas viejas sin ellos)', () {
      final etoro = SupabasePortfolioMapper.positionFromRow({
        'id': 'id1',
        'ticker': 'VOO',
        'quantity': 0.5,
        'purchase_price': 500,
        'purchase_date': '2026-02-01T15:00:00Z',
        'source': 'etoro',
        'synced_at': '2026-10-09T12:00:00Z',
      });
      expect(etoro.source, PositionSource.etoro);
      expect(etoro.syncedAt, DateTime.utc(2026, 10, 9, 12).toLocal());

      final legacy = SupabasePortfolioMapper.positionFromRow({
        'id': 'id2',
        'ticker': 'VOO',
        'quantity': 1,
        'purchase_price': 1,
        'purchase_date': '2026-02-01T15:00:00Z',
      });
      expect(legacy.source, PositionSource.manual);
      expect(legacy.syncedAt, isNull);

      final closed = SupabasePortfolioMapper.closedPositionFromRow({
        'id': 'c1',
        'ticker': 'UNH',
        'quantity': 2,
        'avg_purchase_price': 300,
        'close_price': 320,
        'close_date': '2026-06-24T15:00:00Z',
        'closed_at': '2026-06-24T15:00:00Z',
        'source': 'etoro',
        'realized_pnl': '38.5',
      });
      expect(closed.source, PositionSource.etoro);
      expect(closed.realizedPnl, 38.5);
    });

    test('la app nunca manda el origen al guardar (lo decide la base)', () {
      final row = SupabasePortfolioMapper.positionToRow(
        position: _p('a', PositionSource.etoro),
        userId: 'u',
      );
      expect(row.containsKey('source'), isFalse);
    });
  });

  group('cerradas con P&L del bróker', () {
    ClosedPosition closed({double? realizedPnl}) => ClosedPosition(
      id: 'c',
      ticker: 'UNH',
      quantity: 2,
      avgPurchasePrice: 300,
      closePrice: 320,
      closeDate: DateTime(2026, 6, 24),
      closedAt: DateTime(2026, 6, 24),
      realizedPnl: realizedPnl,
    );

    test('con la ganancia neta de eToro, manda esa (incluye comisiones)', () {
      final c = closed(realizedPnl: 38.5);
      expect(c.hasBrokerPnl, isTrue);
      expect(c.pnlAbsolute, 38.5);
      expect(c.pnlPercent, closeTo(38.5 / 600 * 100, 1e-9));
    });

    test('sin ella, la calcula Porty como siempre', () {
      final c = closed();
      expect(c.hasBrokerPnl, isFalse);
      expect(c.pnlAbsolute, 40);
    });
  });
}
