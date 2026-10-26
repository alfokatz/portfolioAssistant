// Screenshots de "Importar desde un archivo" (inicio, error, leyendo,
// vista previa y listo), en claro y oscuro, con fuentes y textos reales.
// No corre en la suite normal (escribe PNGs):
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
//     flutter test test/screenshots/statement_import_screenshots_test.dart
//
// EXTRA_TRANSLATIONS (opcional): un JSON {"es-ES": {...}} con claves que
// todavía no están en es-ES.json; se suman a las traducciones en memoria.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dartz/dartz.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
// Viene con el SDK (y con easy_localization); solo para estos screenshots.
// ignore: depend_on_referenced_packages
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/company_brand_repository.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/use_cases/add_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_current_price_use_case.dart';
import 'package:portfolio_assistant/features/assistant/services/company_brand_loader.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/statement_import/data/statement_import_client.dart';
import 'package:portfolio_assistant/features/statement_import/domain/import_row.dart';
import 'package:portfolio_assistant/features/statement_import/providers/statement_import_provider.dart';
import 'package:portfolio_assistant/features/statement_import/view/statement_import_screen.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_background_gradient.dart';

final _out = Platform.environment['SCREENSHOTS_OUT'] ?? 'build/screenshots';
final _enabled = Platform.environment['RUN_SCREENSHOTS'] == '1';

const _size = Size(402, 874);
const _dpr = 3.0;

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        File(f).readAsBytes().then((b) => ByteData.view(b.buffer)),
      );
    }
    await loader.load();
  }

  final sdk =
      Platform.environment['FLUTTER_ROOT'] ??
      '${Platform.environment['HOME']}/Development/flutter';
  await load('MaterialIcons', [
    '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
  const weights = {'Regular': 400, 'Medium': 500, 'SemiBold': 600, 'Bold': 700};
  for (final MapEntry(key: name, value: w) in weights.entries) {
    final file = 'assets/fonts/PlusJakartaSans-$name.ttf';
    await load('PlusJakartaSans_${w == 400 ? 'regular' : w}', [file]);
    await load('Plus Jakarta Sans', [file]);
  }
}

/// Un archivo de ejemplo: una lista, una que ya tiene, una sin precio en
/// euros y un ticker que no existe.
class _Client implements StatementImportClient {
  _Client({this.error, this.hang = false});

  final String? error;
  final bool hang;

  /// Lo que escribió: "10 VOO, 2000 dólares en QQQ y algo de NVDA".
  @override
  Future<StatementReadResult> readNote(String note) async =>
      StatementReadResult.fromJson({
        'source': 'ai',
        'rows': [
          {'ticker': 'VOO', 'quantity': 10},
          {'ticker': 'QQQ', 'quantity': 0, 'amount': 2000},
          {'ticker': 'NVDA', 'quantity': 0, 'amount': null},
        ],
      });

  @override
  Future<StatementReadResult> read({
    required String filename,
    required Uint8List bytes,
  }) async {
    if (hang) return Completer<StatementReadResult>().future;
    if (error != null) throw StatementImportException(error!);
    return StatementReadResult.fromJson({
      'source': 'ai',
      'rows': [
        {
          'ticker': 'AAPL',
          'name': 'Apple Inc.',
          'quantity': 12.5,
          'purchase_price': 150.25,
          'purchase_date': '2024-03-15',
        },
        {
          'ticker': 'MSFT',
          'name': 'Microsoft Corp.',
          'quantity': 4,
          'purchase_price': 310,
          'purchase_date': '2023-11-02',
        },
        {
          'ticker': 'SAN.MC',
          'name': 'Banco Santander',
          'quantity': 100,
          'currency': 'EUR',
        },
        {
          'ticker': 'GGAL',
          'name': 'Grupo Financiero Galicia',
          'quantity': 30,
          'purchase_price': 28.4,
          'purchase_date': '2024-06-10',
        },
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

class _NoBrandRepo implements CompanyBrandRepository {
  @override
  Future<CompanyBrand?> getBrand(String ticker) async =>
      CompanyBrand(ticker: ticker);
}

/// Guarda todas menos GGAL (para ver el aviso de las que fallaron).
class _Positions implements PositionRepository {
  @override
  Future<Either<HttpError, Position>> addPosition({
    required String ticker,
    required double quantity,
    required double purchasePrice,
    required DateTime purchaseDate,
  }) async =>
      ticker == 'GGAL'
          ? Left(HttpError(code: 'x', message: 'x'))
          : Right(
            Position(
              id: ticker,
              ticker: ticker,
              quantity: quantity,
              purchasePrice: purchasePrice,
              purchaseDate: purchaseDate,
            ),
          );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Cómo dejar la pantalla antes de la captura.
typedef _Scenario =
    ({
      _Client client,
      Future<void> Function(StatementImportNotifier n, WidgetTester t)? act,
    });

Widget _app(
  Brightness brightness,
  _Client client,
  void Function(StatementImportNotifier) onNotifier,
) {
  final container = ProviderContainer();
  final theme = container.read(
    brightness == Brightness.light
        ? themeDataLightProvider
        : themeDataDarkProvider,
  );
  container.dispose();
  return ProviderScope(
    overrides: [
      companyBrandLoaderProvider.overrideWithValue(
        CompanyBrandLoader(_NoBrandRepo()),
      ),
      statementImportProvider.overrideWith((ref) {
        final n = StatementImportNotifier(
          client: client,
          pick: () async => PickedStatement(name: 'x.pdf', bytes: Uint8List(1)),
          getCurrentPrice: GetCurrentPriceUseCase(quoteRepository: _Quotes()),
          addPosition: AddPositionUseCase(repository: _Positions()),
          heldTickers: () => {'MSFT'},
          positionLimit: () => 10,
        );
        onNotifier(n);
        return n;
      }),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('es', 'ES')],
      locale: const Locale('es', 'ES'),
      builder:
          (context, child) => Stack(
            children: [
              const Positioned.fill(child: AppBackgroundGradient()),
              child!,
            ],
          ),
      home: const StatementImportScreen(),
    ),
  );
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image =
      (await tester.runAsync(() => render.toImage(pixelRatio: _dpr)))!;
  final bytes =
      (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      ))!;
  File('$_out/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes.buffer.asUint8List());
}

void main() {
  setUpAll(() async {
    if (!_enabled) return;
    PortyAvatar.ambientMotion = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    final es =
        jsonDecode(File('assets/translations/es-ES.json').readAsStringSync())
            as Map<String, dynamic>;
    final extra = Platform.environment['EXTRA_TRANSLATIONS'];
    if (extra != null) {
      final json = jsonDecode(File(extra).readAsStringSync()) as Map;
      es.addAll((json['es-ES'] as Map).cast<String, dynamic>());
    }
    Localization.load(const Locale('es', 'ES'), translations: Translations(es));
    await initializeDateFormatting('es_ES');
    Intl.defaultLocale = 'es_ES';
    await _loadFonts();
  });

  Future<void> setUp(WidgetTester tester, Brightness brightness) async {
    tester.view.physicalSize = _size * _dpr;
    tester.view.devicePixelRatio = _dpr;
    tester.view.padding = const FakeViewPadding(top: 47 * _dpr);
    tester.view.viewPadding = const FakeViewPadding(top: 47 * _dpr);
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(seconds: 2));
    }
  }

  Future<void> read(StatementImportNotifier n, WidgetTester t) async {
    await n.pickAndRead();
    await n.checkQuotes();
  }

  final scenarios = <String, _Scenario>{
    'intro': (client: _Client(), act: null),
    'error': (
      client: _Client(error: 'unsupported_type'),
      act: (n, t) => n.pickAndRead(),
    ),
    'quota': (
      client: _Client(error: 'quota_exceeded'),
      act: (n, t) => n.pickAndRead(),
    ),
    'reading': (
      client: _Client(hang: true),
      act: (n, t) async => unawaited(n.pickAndRead()),
    ),
    'preview': (client: _Client(), act: read),
    // "Escribilo": la hoja y lo que sale de leerlo.
    'note_sheet': (
      client: _Client(),
      act: (n, t) async {
        await t.tap(find.text('Escribilo'));
        await t.pump(const Duration(milliseconds: 400));
        await t.enterText(
          find.byType(TextField),
          '10 VOO, 2000 dólares en QQQ y algo de NVDA',
        );
      },
    ),
    'note_preview': (
      client: _Client(),
      act: (n, t) async {
        await n.readNote('10 VOO, 2000 dólares en QQQ y algo de NVDA');
        await n.checkQuotes();
      },
    ),
    'preview_bottom': (
      client: _Client(),
      act: (n, t) async {
        await read(n, t);
        await t.pump();
        n.toggle(3);
        await t.drag(
          find.byType(ListView).first,
          const Offset(0, -600),
          warnIfMissed: false,
        );
      },
    ),
    // La hoja para corregir una fila (la que tiene datos faltantes).
    'edit': (
      client: _Client(),
      act: (n, t) async {
        await read(n, t);
        await t.pump();
        await t.tap(find.text('SAN.MC').first);
        await t.pump();
      },
    ),
    'done': (
      client: _Client(),
      act: (n, t) async {
        await read(n, t);
        n.fillMissingDatesWithToday();
        n.fillMissingPricesWithCurrent();
        n.toggle(4);
        await n.importReady();
      },
    ),
  };

  for (final brightness in Brightness.values) {
    for (final MapEntry(key: name, value: s) in scenarios.entries) {
      final id = 'import_${name}_${brightness.name}';
      testWidgets(id, (tester) async {
        await setUp(tester, brightness);
        final boundary = GlobalKey();
        late StatementImportNotifier notifier;
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: _app(brightness, s.client, (n) => notifier = n),
          ),
        );
        await tester.pump();
        await s.act?.call(notifier, tester);
        await settle(tester);
        await _capture(tester, boundary, id);
      }, skip: !_enabled);
    }
  }
}
