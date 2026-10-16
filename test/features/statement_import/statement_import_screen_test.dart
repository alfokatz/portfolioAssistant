import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/use_cases/add_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_current_price_use_case.dart';
import 'package:portfolio_assistant/features/statement_import/data/statement_import_client.dart';
import 'package:portfolio_assistant/features/statement_import/domain/import_row.dart';
import 'package:portfolio_assistant/features/statement_import/providers/statement_import_provider.dart';
import 'package:portfolio_assistant/features/statement_import/view/statement_import_screen.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

class _Client implements StatementImportClient {
  @override
  Future<StatementReadResult> read({
    required String filename,
    required Uint8List bytes,
  }) async => StatementReadResult.fromJson({
    'source': 'ai',
    'rows': [
      {
        'ticker': 'AAPL',
        'name': 'Apple Inc. Common Stock with a very long name',
        'quantity': 12.5,
        'purchase_price': 150.25,
        'purchase_date': '2024-03-15',
        'currency': 'USD',
      },
      {'ticker': 'SAN.MC', 'quantity': 100, 'currency': 'EUR'},
      {
        'ticker': 'ZZZZ',
        'quantity': 1,
        'purchase_price': 10,
        'purchase_date': '2024-01-01',
      },
    ],
    'warnings': [
      {
        'type': 'non_usd_currency',
        'currencies': ['EUR'],
      },
    ],
  });
}

class _Quotes implements QuoteRepository {
  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async =>
      ticker == 'ZZZZ'
          ? Left(HttpError(code: 'x', message: 'x'))
          : const Right(100);

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) async => const Right([]);

  @override
  Future<List<PriceCandle>> getIntradayCandles(String ticker) async => const [];
}

class _Positions implements PositionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<StatementImportNotifier> pump(
    WidgetTester tester, {
    double width = 320,
    double height = 700,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late StatementImportNotifier notifier;
    final theme = ProviderContainer().read(themeDataLightProvider);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          statementImportProvider.overrideWith((ref) {
            return notifier = StatementImportNotifier(
              client: _Client(),
              pick:
                  () async =>
                      PickedStatement(name: 'x.pdf', bytes: Uint8List(1)),
              getCurrentPrice: GetCurrentPriceUseCase(
                quoteRepository: _Quotes(),
              ),
              addPosition: AddPositionUseCase(repository: _Positions()),
              heldTickers: () => {'AAPL'},
              positionLimit: () => 10,
            );
          }),
        ],
        child: MaterialApp(
          theme: theme,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
          home: const StatementImportScreen(),
        ),
      ),
    );
    return notifier;
  }

  testWidgets('inicio: explica y ofrece elegir el archivo', (tester) async {
    await pump(tester);
    expect(find.text('import_intro_title'), findsOneWidget);
    expect(find.text('import_pick_file'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vista previa en pantalla angosta y texto grande', (
    tester,
  ) async {
    // Alto de sobra: la lista arma solo lo que se ve.
    final notifier = await pump(tester, height: 2400, textScale: 1.6);
    await notifier.pickAndRead();
    await notifier.checkQuotes();
    await tester.pumpAndSettle();
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('SAN.MC'), findsOneWidget);
    // Ya la tiene, precio en otra moneda y ticker desconocido.
    expect(find.text('import_info_held'), findsOneWidget);
    expect(find.text('import_issue_price'), findsOneWidget);
    expect(find.text('import_issue_ticker'), findsOneWidget);
    expect(find.text('import_fill_dates'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
