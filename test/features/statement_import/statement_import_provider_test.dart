import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/use_cases/add_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_current_price_use_case.dart';
import 'package:portfolio_assistant/features/statement_import/data/statement_import_client.dart';
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

StatementReadResult _result(List<Map<String, Object?>> rows) =>
    StatementReadResult.fromJson({'source': 'csv', 'rows': rows});

void main() {
  final today = DateTime(2026, 10, 16, 15);
  final file = PickedStatement(name: 'x.csv', bytes: Uint8List.fromList([1]));

  late _FakePositions positions;
  late int refreshed;

  StatementImportNotifier build({
    required StatementReadResult Function() result,
    Map<String, double> prices = const {'AAPL': 200, 'MSFT': 400, 'VOO': 500},
    Set<String> held = const {},
    int? limit,
    Future<PickedStatement?> Function()? pick,
  }) {
    positions = _FakePositions();
    refreshed = 0;
    return StatementImportNotifier(
      client: _FakeClient(() async => result()),
      pick: pick ?? () async => file,
      getCurrentPrice: GetCurrentPriceUseCase(
        quoteRepository: _FakeQuotes(prices),
      ),
      addPosition: AddPositionUseCase(repository: positions),
      heldTickers: () => held,
      positionLimit: () => limit,
      onImported: () async => refreshed++,
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
          held: {'VOO'},
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

  test('parseUserNumber acepta coma o punto decimal', () {
    expect(parseUserNumber('1.234,5'), 1234.5);
    expect(parseUserNumber('1,234.5'), 1234.5);
    expect(parseUserNumber('12,5'), 12.5);
    expect(parseUserNumber(''), isNull);
    expect(parseUserNumber('abc'), isNull);
  });
}
