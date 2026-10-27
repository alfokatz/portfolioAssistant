import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/closed_position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/use_cases/add_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/close_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_current_price_use_case.dart';
import 'package:portfolio_assistant/features/statement_import/data/statement_import_client.dart';
import 'package:portfolio_assistant/features/statement_import/domain/holding_change.dart';
import 'package:portfolio_assistant/features/statement_import/domain/import_row.dart';
import 'package:portfolio_assistant/features/statement_import/providers/statement_import_provider.dart';
import 'package:portfolio_assistant/shared/utils/user_number.dart';

class _FakeClient implements StatementImportClient {
  _FakeClient(this.respond);

  final Future<StatementReadResult> Function() respond;
  int calls = 0;

  @override
  Future<StatementReadResult> read({
    required String filename,
    required Uint8List bytes,
  }) {
    calls++;
    return respond();
  }

  final notes = <String>[];

  @override
  Future<StatementReadResult> readNote(String note) {
    notes.add(note);
    return respond();
  }
}

class _FakeQuotes implements QuoteRepository {
  _FakeQuotes(this.prices);

  final Map<String, double> prices;

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async {
    final p = prices[ticker];
    return p == null
        ? Left(HttpError(code: 'x', message: 'no quote'))
        : Right(p);
  }

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) async => const Right([]);

  @override
  Future<List<PriceCandle>> getIntradayCandles(String ticker) async => const [];
}

class _FakePositions implements PositionRepository {
  final added = <String>[];
  final addedParams = <AddPositionParams>[];
  Set<String> failing = {};

  @override
  Future<Either<HttpError, Position>> addPosition({
    required String ticker,
    required double quantity,
    required double purchasePrice,
    required DateTime purchaseDate,
  }) async {
    if (failing.contains(ticker)) {
      return Left(HttpError(code: 'x', message: 'fail'));
    }
    added.add(ticker);
    addedParams.add(
      AddPositionParams(
        ticker: ticker,
        quantity: quantity,
        purchasePrice: purchasePrice,
        purchaseDate: purchaseDate,
      ),
    );
    return Right(
      Position(
        id: ticker,
        ticker: ticker,
        quantity: quantity,
        purchasePrice: purchasePrice,
        purchaseDate: purchaseDate,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClosed implements ClosedPositionRepository {
  final closed = <ClosePositionParams>[];

  @override
  Future<Either<HttpError, ClosedPosition>> closePosition({
    required String positionId,
    required double quantity,
    required double closePrice,
    required DateTime closeDate,
  }) async {
    closed.add(
      ClosePositionParams(
        positionId: positionId,
        quantity: quantity,
        closePrice: closePrice,
        closeDate: closeDate,
      ),
    );
    return Right(
      ClosedPosition(
        id: positionId,
        ticker: positionId,
        quantity: quantity,
        avgPurchasePrice: 1,
        closePrice: closePrice,
        closeDate: closeDate,
        closedAt: closeDate,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Lo que tiene en manuales: unidades y costo total.
HeldHolding _held(double quantity, double cost, {double? price}) =>
    HeldHolding(quantity: quantity, costBasis: cost, currentPrice: price);

StatementReadResult _result(List<Map<String, Object?>> rows) =>
    StatementReadResult.fromJson({'source': 'csv', 'rows': rows});

void main() {
  final today = DateTime(2026, 10, 16, 15);
  final file = PickedStatement(name: 'x.csv', bytes: Uint8List.fromList([1]));

  late _FakePositions positions;
  late _FakeClosed closes;
  late int refreshed;

  StatementImportNotifier build({
    required StatementReadResult Function() result,
    Map<String, double> prices = const {'AAPL': 200, 'MSFT': 400, 'VOO': 500},
    Map<String, HeldHolding> held = const {},
    int? limit,
    Future<PickedStatement?> Function()? pick,
  }) {
    positions = _FakePositions();
    closes = _FakeClosed();
    refreshed = 0;
    return StatementImportNotifier(
      client: _FakeClient(() async => result()),
      pick: pick ?? () async => file,
      getCurrentPrice: GetCurrentPriceUseCase(
        quoteRepository: _FakeQuotes(prices),
      ),
      addPosition: AddPositionUseCase(repository: positions),
      closePosition: ClosePositionUseCase(repository: closes),
      held: () => held,
      positionLimit: () => limit,
      onImported: (_) async => refreshed++,
      now: () => today,
    );
  }

  group('StatementReadResult.fromJson', () {
    test('lee filas, avisos y descarta lo inválido', () {
      final r = StatementReadResult.fromJson({
        'source': 'ai',
        'rows': [
          {
            'ticker': 'aapl',
            'name': 'Apple',
            'quantity': 2,
            'purchase_price': 150,
            'purchase_date': '2024-03-15',
            'currency': 'USD',
          },
          {'ticker': '', 'quantity': 1},
          {'ticker': 'MSFT', 'quantity': 'x'},
        ],
        'warnings': [
          {
            'type': 'non_usd_currency',
            'currencies': ['EUR'],
          },
          {'type': 'truncated', 'limit': 200},
          'basura',
        ],
      });
      expect(r.source, ImportSource.ai);
      expect(r.rows, hasLength(1));
      expect(r.rows.single.ticker, 'AAPL');
      expect(r.rows.single.purchaseDate, DateTime(2024, 3, 15));
      // La cotización pendiente no la vuelve incompleta: el botón espera
      // a que termine el chequeo (`checkingQuotes`).
      expect(r.rows.single.isReady, isTrue);
      expect(r.warnings.map((w) => w.type), ['non_usd_currency', 'truncated']);
      expect(r.warnings.last.count, 200);
    });
  });

  group('StatementImportNotifier', () {
    test(
      'lee el archivo, chequea los tickers y marca los desconocidos',
      () async {
        final n = build(
          result:
              () => _result([
                {
                  'ticker': 'AAPL',
                  'quantity': 1,
                  'purchase_price': 100,
                  'purchase_date': '2024-01-01',
                },
                {
                  'ticker': 'ZZZZ',
                  'quantity': 1,
                  'purchase_price': 10,
                  'purchase_date': '2024-01-01',
                },
              ]),
        );
        await n.pickAndRead();
        await n.checkQuotes();
        final s = n.state;
        expect(s.phase, ImportPhase.preview);
        expect(s.rows.map((r) => r.quote), [
          QuoteCheck.found,
          QuoteCheck.notFound,
        ]);
        expect(s.ready.map((r) => r.ticker), ['AAPL']);
        expect(s.needsAttention, 1);
        expect(s.canImport, isTrue);
      },
    );

    test('lo que escribe: con monto en dinero, la cantidad sale del precio de '
        'hoy; sin nada, queda para completar', () async {
      final n = build(
        result:
            () => _result([
              {'ticker': 'VOO', 'quantity': 10},
              {'ticker': 'AAPL', 'quantity': 0, 'amount': 1000},
              {'ticker': 'MSFT', 'quantity': 0, 'amount': null},
            ]),
      );
      await n.readNote('  10 VOO, 1000 dólares en Apple y algo de Microsoft ');
      await n.checkQuotes();
      final rows = {for (final r in n.state.rows) r.ticker: r};
      expect(n.state.origin, ImportOrigin.note);
      expect(rows['VOO']!.quantity, 10);
      expect(rows['VOO']!.quantityFromAmount, isFalse);
      // 1000 / 200 (AAPL hoy).
      expect(rows['AAPL']!.quantity, 5);
      expect(rows['AAPL']!.quantityFromAmount, isTrue);
      expect(rows['AAPL']!.issues.contains(ImportIssue.quantity), isFalse);
      expect(rows['MSFT']!.issues, contains(ImportIssue.quantity));
      // Corregirla a mano le saca la marca de "calculada".
      n.updateRow(rows['AAPL']!.id, quantity: 4);
      expect(
        n.state.rows.firstWhere((r) => r.ticker == 'AAPL').quantityFromAmount,
        isFalse,
      );
    });

    test('al importar, avisa por qué camino llegó la cartera', () async {
      ImportOrigin? origin;
      final n = StatementImportNotifier(
        client: _FakeClient(
          () async => _result([
            {
              'ticker': 'AAPL',
              'quantity': 1,
              'purchase_price': 100,
              'purchase_date': '2024-01-01',
            },
          ]),
        ),
        pick: () async => file,
        pickScreenshot: () async => file,
        getCurrentPrice: GetCurrentPriceUseCase(
          quoteRepository: _FakeQuotes(const {'AAPL': 200}),
        ),
        addPosition: AddPositionUseCase(repository: _FakePositions()),
        closePosition: ClosePositionUseCase(repository: _FakeClosed()),
        held: () => const {},
        positionLimit: () => null,
        onImported: (o) async => origin = o,
        now: () => today,
      );
      await n.pickScreenshotAndRead();
      await n.checkQuotes();
      await n.importReady();
      expect(origin, ImportOrigin.screenshot);
      expect(ImportOrigin.screenshot.loadMethod, 'screenshot');
    });

    test('si el usuario cancela el selector no pasa nada', () async {
      final n = build(result: () => _result([]), pick: () async => null);
      await n.pickAndRead();
      expect(n.state.phase, ImportPhase.intro);
    });

    test('un error del servidor vuelve al inicio con el tipo', () async {
      final n = build(
        result: () => throw const StatementImportException('nothing_found'),
      );
      await n.pickAndRead();
      expect(n.state.phase, ImportPhase.intro);
      expect(n.state.errorType, 'nothing_found');
    });

    test('completa fechas con hoy y precios con el de hoy', () async {
      final n = build(
        result:
            () => _result([
              {'ticker': 'MSFT', 'quantity': 3},
            ]),
      );
      await n.read(file);
      await n.checkQuotes();
      expect(n.state.missingDates, 1);
      expect(n.state.missingPricesFillable, 1);
      n.fillMissingDatesWithToday();
      n.fillMissingPricesWithCurrent();
      final row = n.state.rows.single;
      expect(row.purchaseDate, DateTime(2026, 10, 16));
      expect(row.purchasePrice, 400);
      expect(row.isReady, isTrue);
    });

    test('editar el ticker vuelve a buscar su cotización', () async {
      final n = build(
        result:
            () => _result([
              {
                'ticker': 'APPL',
                'quantity': 1,
                'purchase_price': 10,
                'purchase_date': '2024-01-01',
              },
            ]),
      );
      await n.read(file);
      await n.checkQuotes();
      expect(n.state.rows.single.quote, QuoteCheck.notFound);
      n.updateRow(n.state.rows.single.id, ticker: 'aapl');
      await n.checkQuotes();
      expect(n.state.rows.single.ticker, 'AAPL');
      expect(n.state.rows.single.quote, QuoteCheck.found);
    });

    test(
      'respeta el tope de posiciones del plan (tickers distintos)',
      () async {
        final n = build(
          held: {'VOO': _held(1, 10)},
          limit: 2,
          result:
              () => _result([
                for (final t in ['AAPL', 'MSFT', 'VOO'])
                  {
                    'ticker': t,
                    'quantity': 1,
                    'purchase_price': 10,
                    'purchase_date': '2024-01-01',
                  },
              ]),
        );
        await n.read(file);
        await n.checkQuotes();
        // VOO ya está; AAPL y MSFT serían 3 en total.
        expect(n.state.exceedsLimit, isTrue);
        expect(n.state.canImport, isFalse);
        n.toggle(n.state.rows.firstWhere((r) => r.ticker == 'MSFT').id);
        expect(n.state.exceedsLimit, isFalse);
        expect(n.state.canImport, isTrue);
      },
    );

    test('importa solo las listas e informa las que fallan', () async {
      final n = build(
        result:
            () => _result([
              {
                'ticker': 'AAPL',
                'quantity': 1,
                'purchase_price': 10,
                'purchase_date': '2024-01-01',
              },
              {
                'ticker': 'MSFT',
                'quantity': 2,
                'purchase_price': 20,
                'purchase_date': '2024-01-01',
              },
              {'ticker': 'VOO', 'quantity': 1},
            ]),
      );
      await n.read(file);
      await n.checkQuotes();
      positions.failing = {'MSFT'};
      await n.importReady();
      expect(positions.added, ['AAPL']);
      expect(n.state.phase, ImportPhase.done);
      expect(n.state.importedCount, 1);
      expect(n.state.failedTickers, ['MSFT']);
      expect(refreshed, 1);
    });
  });

  group('comparación con la cartera', () {
    Map<String, Object?> row(String t, num q, {num? price}) => {
      'ticker': t,
      'quantity': q,
      'purchase_price': price ?? 100,
      'purchase_date': '2024-01-01',
    };

    test(
      'compra la diferencia, vende lo que sobra y no toca lo igual',
      () async {
        final n = build(
          held: {
            // 10 a 100 de promedio; el archivo dice 13 a 110.
            'AAPL': _held(10, 1000, price: 200),
            'MSFT': _held(5, 1500, price: 400),
            'VOO': _held(2, 800, price: 500),
          },
          result:
              () => _result([
                row('AAPL', 13, price: 110),
                row('MSFT', 3),
                row('VOO', 2),
              ]),
        );
        await n.read(file);
        await n.checkQuotes();
        final s = n.state;
        final plans = {for (final r in s.rows) r.ticker: s.planFor(r)};
        expect(plans['AAPL']!.action, ImportAction.buyMore);
        expect(plans['AAPL']!.quantity, 3);
        // (13 × 110 − 1000) / 3: lo que pagó por las 3 de más.
        expect(plans['AAPL']!.price, closeTo(143.333333, 1e-6));
        expect(plans['MSFT']!.action, ImportAction.sell);
        expect(plans['MSFT']!.quantity, 2);
        expect(plans['MSFT']!.price, 400);
        expect(plans['VOO']!.action, ImportAction.unchanged);
        expect(s.ready.map((r) => r.ticker), ['AAPL', 'MSFT']);
        expect(s.needsAttention, 0);
        expect(s.unchangedCount, 1);
        expect(s.changedCount, 2);
        expect(s.onlyAdds, isFalse);
        expect(s.newTickers, isEmpty);

        await n.importReady();
        final today0 = DateTime(2026, 10, 16);
        final buy = positions.addedParams.single;
        expect(buy.ticker, 'AAPL');
        expect(buy.quantity, 3);
        expect(buy.purchaseDate, today0);
        final sell = closes.closed.single;
        expect(sell.positionId, 'MSFT');
        expect(sell.quantity, 2);
        expect(sell.closePrice, 400);
        expect(sell.closeDate, today0);
        expect(n.state.importedCount, 2);
      },
    );

    test(
      'lo que tiene y no está en el archivo se vende solo si lo marca',
      () async {
        final n = build(
          held: {'TSLA': _held(4, 800, price: 250)},
          result: () => _result([row('AAPL', 1)]),
        );
        await n.read(file);
        await n.checkQuotes();
        expect(n.state.missing, ['TSLA']);
        expect(n.state.onlyAdds, isTrue);
        n.toggleMissing('TSLA');
        expect(n.state.changesToApply, 2);
        await n.importReady();
        expect(positions.added, ['AAPL']);
        expect(closes.closed.single.positionId, 'TSLA');
        expect(closes.closed.single.quantity, 4);
        expect(closes.closed.single.closePrice, 250);
      },
    );

    test('con una nota o captura no ofrece vender lo que falta', () async {
      final n = build(
        held: {'TSLA': _held(4, 800, price: 250)},
        result: () => _result([row('AAPL', 1)]),
      );
      await n.readNote('1 AAPL');
      expect(n.state.missing, isEmpty);
    });

    test('lo que ya llega de un bróker arranca afuera', () async {
      final n = build(
        held: {
          'AAPL': const HeldHolding(
            quantity: 0,
            costBasis: 0,
            broker: PositionSource.etoro,
          ),
        },
        result: () => _result([row('AAPL', 3), row('MSFT', 1)]),
      );
      await n.read(file);
      await n.checkQuotes();
      final aapl = n.state.rows.firstWhere((r) => r.ticker == 'AAPL');
      expect(aapl.included, isFalse);
      expect(n.state.ready.map((r) => r.ticker), ['MSFT']);
      // No es un ticker nuevo para el tope del plan.
      n.toggle(aapl.id);
      expect(n.state.newTickers, {'MSFT'});
    });
  });

  group('HoldingDiff', () {
    ImportRow r(double q, {double? price, bool fromAmount = false}) =>
        ImportRow(
          id: 0,
          ticker: 'AAPL',
          quantity: q,
          purchasePrice: price,
          quantityFromAmount: fromAmount,
        );

    test('sin manuales es una compra nueva', () {
      expect(HoldingDiff.plan(r(3), null, 200).action, ImportAction.add);
      expect(HoldingDiff.plan(r(3), _held(0, 0), 200).action, ImportAction.add);
    });

    test('redondeos del bróker cuentan como iguales', () {
      expect(
        HoldingDiff.plan(r(10.0004), _held(10, 1000), 200).action,
        ImportAction.unchanged,
      );
      // Con la cantidad calculada desde un monto se tolera un 2 %.
      expect(
        HoldingDiff.plan(
          r(10.15, fromAmount: true),
          _held(10, 1000),
          200,
        ).action,
        ImportAction.unchanged,
      );
    });

    test('un precio deducido absurdo cae al de hoy', () {
      // El promedio del archivo es menor que el propio: daría negativo.
      final plan = HoldingDiff.plan(r(12, price: 50), _held(10, 1000), 200);
      expect(plan.action, ImportAction.buyMore);
      expect(plan.price, 200);
      // Sin promedio en el archivo, también el de hoy.
      expect(HoldingDiff.plan(r(12), _held(10, 1000), 200).price, 200);
    });

    test('fromLots suma solo lo manual y recuerda el bróker', () {
      PositionValuation lot(String t, double q, double p, PositionSource s) =>
          PositionValuation(
            position: Position(
              id: '$t$q',
              ticker: t,
              quantity: q,
              purchasePrice: p,
              purchaseDate: DateTime(2024),
              source: s,
            ),
            currentPrice: 200,
            marketValue: q * 200,
            pnlAbsolute: 0,
            pnlPercent: 0,
          );
      final held = HeldHolding.fromLots([
        lot('AAPL', 2, 100, PositionSource.manual),
        lot('AAPL', 3, 120, PositionSource.manual),
        lot('AAPL', 5, 90, PositionSource.etoro),
      ]);
      expect(held['AAPL']!.quantity, 5);
      expect(held['AAPL']!.costBasis, 560);
      expect(held['AAPL']!.currentPrice, 200);
      expect(held['AAPL']!.broker, PositionSource.etoro);
    });
  });

  test('parseUserNumber acepta coma o punto decimal', () {
    expect(parseUserNumber('1.234,5'), 1234.5);
    expect(parseUserNumber('1,234.5'), 1234.5);
    expect(parseUserNumber('12,5'), 12.5);
    expect(parseUserNumber(''), isNull);
    expect(parseUserNumber('abc'), isNull);
  });
}
