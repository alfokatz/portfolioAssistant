import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/services/chat_dictation.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_composer_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/closed_position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/company_brand_repository.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/use_cases/add_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/close_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_current_price_use_case.dart';
import 'package:portfolio_assistant/features/assistant/services/company_brand_loader.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/statement_import/data/statement_import_client.dart';
import 'package:portfolio_assistant/features/statement_import/domain/holding_change.dart';
import 'package:portfolio_assistant/features/statement_import/domain/import_row.dart';
import 'package:portfolio_assistant/features/statement_import/providers/statement_import_provider.dart';
import 'package:portfolio_assistant/features/statement_import/view/statement_import_screen.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

class _Client implements StatementImportClient {
  @override
  Future<StatementReadResult> readNote(String note) =>
      read(filename: 'nota', bytes: Uint8List(0));

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

/// Sin logos: los avatares muestran el monograma (y no reintentan).
class _NoBrandRepo implements CompanyBrandRepository {
  @override
  Future<CompanyBrand?> getBrand(String ticker) async =>
      CompanyBrand(ticker: ticker);
}

class _FailingClient implements StatementImportClient {
  @override
  Future<StatementReadResult> read({
    required String filename,
    required Uint8List bytes,
  }) async => throw const StatementImportException('nothing_found');

  @override
  Future<StatementReadResult> readNote(String note) async =>
      throw const StatementImportException('nothing_found');
}

/// Dictado falso: al empezar "escucha" una frase y la escribe.
class _Dictation extends ChatDictation {
  bool listening = false;
  bool canceled = false;

  @override
  bool get isListening => listening;

  @override
  Future<DictationFailure?> start({
    required String languageCode,
    required ValueChanged<String> onText,
  }) async {
    listening = true;
    notifyListeners();
    onText('diez VOO y dos mil dólares en cu cu cu');
    return null;
  }

  @override
  Future<void> stop() async {
    listening = false;
    notifyListeners();
  }

  @override
  Future<void> cancel() async {
    canceled = true;
    listening = false;
  }
}

class _Positions implements PositionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Closed implements ClosedPositionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => PortyAvatar.ambientMotion = false);
  tearDownAll(() => PortyAvatar.ambientMotion = true);

  Future<StatementImportNotifier> pump(
    WidgetTester tester, {
    StatementImportClient? client,
    double width = 320,
    double height = 700,
    double textScale = 1,
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late StatementImportNotifier notifier;
    final theme = ProviderContainer().read(themeDataLightProvider);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides,
          companyBrandLoaderProvider.overrideWithValue(
            CompanyBrandLoader(_NoBrandRepo()),
          ),
          statementImportProvider.overrideWith((ref) {
            return notifier = StatementImportNotifier(
              client: client ?? _Client(),
              pick:
                  () async =>
                      PickedStatement(name: 'x.pdf', bytes: Uint8List(1)),
              getCurrentPrice: GetCurrentPriceUseCase(
                quoteRepository: _Quotes(),
              ),
              addPosition: AddPositionUseCase(repository: _Positions()),
              closePosition: ClosePositionUseCase(repository: _Closed()),
              // AAPL: tiene 10 y el archivo dice 12,5. TSLA no está en el
              // archivo.
              held:
                  () => const {
                    'AAPL': HeldHolding(
                      quantity: 10,
                      costBasis: 1500,
                      currentPrice: 100,
                    ),
                    'TSLA': HeldHolding(
                      quantity: 4,
                      costBasis: 800,
                      currentPrice: 250,
                    ),
                  },
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

  testWidgets('inicio: tres formas de traerla (archivo, captura, escribirla)', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();
    expect(find.text('statement_import_intro_porty'), findsOneWidget);
    expect(find.text('statement_import_way_file_title'), findsOneWidget);
    expect(find.text('statement_import_way_screenshot_title'), findsOneWidget);
    expect(find.text('statement_import_way_write_title'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('decirla: el micrófono escribe lo dictado y se manda igual', (
    tester,
  ) async {
    final dictation = _Dictation();
    await pump(
      tester,
      height: 2400,
      overrides: [chatDictationProvider.overrideWith((ref) => dictation)],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('statement_import_way_write_title'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AssistantMicButton));
    // La frase de Porty cambia con un fundido.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('statement_import_note_listening'), findsOneWidget);
    expect(find.text('diez VOO y dos mil dólares en cu cu cu'), findsOneWidget);
    await tester.tap(find.byType(AssistantMicButton));
    await tester.pump();
    await tester.tap(find.text('statement_import_note_send'));
    await tester.pumpAndSettle();
    // Al mandar se corta el dictado (no vuelve a escribir nada).
    expect(dictation.canceled, isTrue);
    expect(find.text('statement_import_preview_porty_note'), findsOneWidget);
  });

  testWidgets('escribirla: la hoja manda el texto y sale la vista previa', (
    tester,
  ) async {
    await pump(tester, height: 2400);
    await tester.pumpAndSettle();
    await tester.tap(find.text('statement_import_way_write_title'));
    await tester.pumpAndSettle();
    expect(find.text('statement_import_note_porty'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '10 VOO y algo de NVDA');
    await tester.pumpAndSettle();
    await tester.tap(find.text('statement_import_note_send'));
    await tester.pumpAndSettle();
    expect(find.text('statement_import_preview_porty_note'), findsOneWidget);
    expect(find.text('statement_import_list_title_note'), findsOneWidget);
    // Fecha y precio de hoy donde no los dijo.
    expect(find.text('statement_import_preview_note_filled'), findsOneWidget);
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
    // Ya la tiene (se compra la diferencia), precio en otra moneda y ticker
    // desconocido.
    expect(find.text('statement_import_preview_porty'), findsOneWidget);
    expect(find.text('statement_import_compare_note'), findsOneWidget);
    expect(find.text('statement_import_held_line'), findsOneWidget);
    expect(find.text('statement_import_tag_buy_more_at'), findsOneWidget);
    expect(find.text('statement_import_tag_price'), findsOneWidget);
    expect(find.text('statement_import_tag_currency'), findsOneWidget);
    expect(find.text('statement_import_tag_ticker'), findsOneWidget);
    expect(find.text('import_fill_dates'), findsOneWidget);
    // Lo que tiene y no vino en el archivo, sin marcar.
    expect(find.text('statement_import_missing_title'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('statement_import_missing_keep'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('statement_import_missing_keep'), findsOneWidget);
    // Comprar la diferencia de AAPL es el único cambio.
    expect(find.text('import_cta_changes_one'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('TSLA'));
    await tester.pumpAndSettle();
    expect(find.text('statement_import_missing_sell'), findsOneWidget);
    expect(notifier.state.sellMissing, {'TSLA'});
    expect(find.text('import_cta_changes'), findsOneWidget);

    // Descartar una fila la marca como fuera de la importación.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('statement_import_tag_excluded'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error: Porty dice qué pasó y ofrece elegir otro archivo', (
    tester,
  ) async {
    final notifier = await pump(tester, client: _FailingClient());
    await notifier.pickAndRead();
    await tester.pumpAndSettle();
    expect(find.text('statement_import_error_nothing_found'), findsOneWidget);
    expect(find.text('statement_import_pick_again'), findsOneWidget);
    expect(find.text('statement_import_intro_porty'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
