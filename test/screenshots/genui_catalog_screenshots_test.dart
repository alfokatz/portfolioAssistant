// Screenshots de cada widget del catálogo GenUI (el ejemplo de cada
// CatalogItem), con fuentes reales y el tema claro de la app. No corre en la
// suite normal (escribe PNGs):
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
//     flutter test test/screenshots/genui_catalog_screenshots_test.dart
//
// Con LOGO_BASE_URL=http://127.0.0.1:8787 las cards muestran logos reales:
// cada ticker carga <LOGO_BASE_URL>/<TICKER>.png (servido desde una carpeta
// local, por ejemplo con `python3 -m http.server 8787`). Sin la variable,
// quedan las iniciales (el test no tiene red). Lo usan las piezas de
// marketing (tools/marketing/).
//
// Con TICKER_SWAP=VOO:SPY (pares separados por coma) se reemplazan tickers en
// los datos de ejemplo y la evidencia, solo para estas capturas: los ejemplos
// de lib/ no se tocan porque forman parte del prompt (allowlist de ai-chat).
//
// Con DEMO_PRICES=1 los gráficos de precios (QaCompareChart) reciben una serie
// de demo determinística en vez de pedir cotizaciones (el test no tiene red).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/domain/repositories/company_brand_repository.dart';
import 'package:portfolio_assistant/features/assistant/services/company_brand_loader.dart';
import 'package:portfolio_assistant/features/assistant/services/price_chart_data_loader.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'dart:math' as math;
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/data/market/dividend_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/buy_plan_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/assistant/tools/advice_tools.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

import '../helpers/genui_test_helpers.dart';

/// Tool calls detrás de las cards que leen sus datos de la evidencia del
/// turno (el ejemplo del catálogo solo trae el id).
final _evidence = <String, List<ToolCallRecord>>{
  'QaSavingsPlan': [
    ToolCallRecord(
      name: GetGoalProjectionTool.toolName,
      args: const {},
      result: {
        'status': 'ok',
        ...GoalProjectionBuilder.build(
          currentPortfolioValue: 12000,
          desiredMonthlyIncome: 3000,
          targetDate: DateTime(2051, 10, 9),
          label: 'Jubilación',
          asOf: DateTime(2026, 10, 9),
        ),
        GoalProjectionBuilder.planIdKey: 'plan-1a2b3c4d',
      },
    ),
  ],
  'QaWatchlist': [
    const ToolCallRecord(
      name: 'get_watchlist',
      args: {},
      result: {
        'status': 'ok',
        'items': [
          {
            'ticker': 'TSLA',
            'price': 373.25,
            'day_change_pct': -0.36,
            'since_added_pct': -0.36,
            'alerts_on': true,
          },
          {
            'ticker': 'NFLX',
            'price': 66.64,
            'day_change_pct': -0.61,
            'since_added_pct': -0.57,
            'alerts_on': false,
          },
          {
            'ticker': 'GGAL',
            'price': 36.16,
            'day_change_pct': 0.11,
            'since_added_pct': 0.39,
            'alerts_on': true,
          },
        ],
      },
    ),
  ],
  'QaWeeklyReport': [
    const ToolCallRecord(
      name: 'get_weekly_report',
      args: {},
      result: {
        'status': 'ok',
        'report': {
          'week': '2026-10-19',
          'change_pct': 2.4,
          'change_abs': 312.5,
          'sp500_pct': 1.1,
          'movers': [
            {
              'ticker': 'NVDA',
              'move_pct': 6.1,
              'why':
                  'Subió después de presentar resultados mejores que lo '
                  'esperado.',
            },
            {'ticker': 'AAPL', 'move_pct': -1.2},
            {'ticker': 'VOO', 'move_pct': 1.0},
          ],
          'reading':
              'Una semana buena: NVDA empujó casi toda la suba y el resto '
              'acompañó al mercado.',
        },
      },
    ),
  ],
  'QaAllocationPlan': [
    const ToolCallRecord(
      name: 'get_allocation_plan',
      args: {'contribution_usd': 500},
      result: {
        'status': 'ok',
        'drift_threshold': 5.0,
        'portfolio_value_usd': 10000.0,
        'rows': [
          {
            'ticker': 'VOO',
            'current_pct': 34.6,
            'target_pct': 43,
            'drift_pts': -8.4,
          },
          {
            'ticker': 'GOOGL',
            'current_pct': 22.0,
            'target_pct': 25,
            'drift_pts': -3.0,
          },
          {
            'ticker': 'AAPL',
            'current_pct': 25.7,
            'target_pct': 11,
            'drift_pts': 14.7,
          },
          {
            'ticker': 'SGOV',
            'current_pct': 13.3,
            'target_pct': 21,
            'drift_pts': -7.7,
          },
          {
            'ticker': 'DUOL',
            'current_pct': 4.4,
            'target_pct': 0,
            'drift_pts': 4.4,
          },
        ],
        'contribution': {
          'amount_usd': 500.0,
          'split': [
            {'ticker': 'VOO', 'amount_usd': 226.0},
            {'ticker': 'GOOGL', 'amount_usd': 144.0},
            {'ticker': 'SGOV', 'amount_usd': 130.0},
          ],
        },
      },
    ),
  ],
  'QaBuyPlan': [
    ToolCallRecord(
      name: GetMonthlyBuyPlanTool.toolName,
      args: const {},
      result: {
        ...BuyPlanBuilder.build(
          base: GoalProjectionBuilder.build(
            currentPortfolioValue: 12000,
            desiredMonthlyIncome: 3000,
            targetDate: DateTime(2051, 10, 9),
            asOf: DateTime(2026, 10, 9),
          ),
          picks: const [
            BuyPlanPick('SCHD', PlanAssetClass.equities),
            BuyPlanPick('VYM', PlanAssetClass.equities),
            BuyPlanPick('KO', PlanAssetClass.equities),
            BuyPlanPick('BND', PlanAssetClass.bonds),
            BuyPlanPick('SGOV', PlanAssetClass.cash),
          ],
          info: {
            'SCHD': _div('Schwab US Dividend Equity ETF', 0.0362),
            'VYM': _div('Vanguard High Dividend Yield ETF', 0.0281),
            'KO': _div('The Coca-Cola Company', 0.0293, etf: false),
            'BND': _div('Vanguard Total Bond Market ETF', 0.0376),
            'SGOV': _div('iShares 0-3 Month Treasury Bond ETF', 0.0452),
          },
        ),
        BuyPlanBuilder.buyPlanIdKey: 'buy-1a2b3c4d',
      },
    ),
  ],
};

Map<String, Object?> _div(String name, double y, {bool etf = true}) =>
    DividendFetcher.parse({
      'quoteType': {'quoteType': etf ? 'ETF' : 'EQUITY', 'longName': name},
      'summaryDetail': {
        etf ? 'yield' : 'dividendYield': {'raw': y},
      },
    });

final _out = Platform.environment['SCREENSHOTS_OUT'] ?? 'build/screenshots';
final _enabled = Platform.environment['RUN_SCREENSHOTS'] == '1';

final _logoBase = Platform.environment['LOGO_BASE_URL'];

final _tickerSwap = {
  for (final pair in (Platform.environment['TICKER_SWAP'] ?? '').split(','))
    if (pair.contains(':')) pair.split(':').first: pair.split(':').last,
};

/// Reemplaza tickers como palabra completa (ver TICKER_SWAP en la cabecera).
String _swapText(String text) {
  var out = text;
  _tickerSwap.forEach((from, to) {
    out = out.replaceAll(RegExp('\\b$from\\b'), to);
  });
  return out;
}

Object? _swapDeep(Object? value) => switch (value) {
  String s => _swapText(s),
  Map m => <String, Object?>{
    for (final e in m.entries) e.key as String: _swapDeep(e.value),
  },
  List l => [for (final v in l) _swapDeep(v)],
  _ => value,
};

List<ToolCallRecord> _evidenceFor(String name) => [
  for (final call in _evidence[name] ?? const <ToolCallRecord>[])
    _tickerSwap.isEmpty
        ? call
        : ToolCallRecord(
          name: call.name,
          args: call.args,
          result: _swapDeep(call.result)! as Map<String, Object?>,
        ),
];

/// Logos servidos desde [_logoBase] (ver la cabecera del archivo).
class _LocalLogoRepository implements CompanyBrandRepository {
  @override
  Future<CompanyBrand?> getBrand(String ticker) async =>
      CompanyBrand(ticker: ticker, logoUrl: '$_logoBase/$ticker.png');
}

final _demoPrices = Platform.environment['DEMO_PRICES'] == '1';

/// Serie de demo: paseo suave y determinístico por ticker que termina en la
/// variación del ejemplo de la card (o ±1,5 % si el ticker no está).
class _DemoPriceLoader implements PriceChartDataLoader {
  static const _endPct = {
    'QQQ': -1.96,
    'SPY': 1.39,
    'AAPL': -1.96,
    'MSFT': 1.39,
  };

  @override
  Future<List<PriceCandle>?> load(String ticker, PriceChartRange range) async {
    const n = 22;
    final seed = ticker.codeUnits.fold<int>(7, (a, c) => a * 31 + c);
    final rnd = math.Random(seed);
    final end = (_endPct[ticker] ?? 1.5) / 100;
    var walk = 0.0;
    final noise = <double>[];
    for (var i = 0; i < n; i++) {
      walk += (rnd.nextDouble() - .5) * .012;
      noise.add(walk);
    }
    final start = DateTime(2026, 9, 21);
    return [
      for (var i = 0; i < n; i++)
        PriceCandle(
          date: start.add(Duration(days: i + (i ~/ 5) * 2)),
          // Tendencia lineal al final + ruido que vuelve a 0 en los extremos.
          close:
              100 *
              (1 +
                  end * i / (n - 1) +
                  (noise[i] - noise.last * i / (n - 1)) -
                  noise.first * (1 - i / (n - 1))),
        ),
    ];
  }
}

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

void main() {
  setUpAll(() async {
    if (!_enabled) return;
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    // flutter_test responde 400 a todo pedido HTTP; con logos locales hace
    // falta el cliente real (solo habla con 127.0.0.1).
    if (_logoBase != null) HttpOverrides.global = null;
  });

  final catalog = AssistantCatalog.build();
  final names = <String>{};
  for (final item in catalog.items) {
    if (!item.name.startsWith('Qa') || !names.add(item.name)) continue;
    for (var e = 0; e < item.exampleData.length; e++) {
      for (final brightness in Brightness.values) {
        final name = '${item.name}_${e}_${brightness.name}';
        testWidgets(name, (tester) async {
          const size = Size(390, 1400);
          tester.view.physicalSize = size * 2;
          tester.view.devicePixelRatio = 2;
          addTearDown(tester.view.reset);
          QaColors.resolve(brightness);
          final container = ProviderContainer(
            overrides: [
              if (_logoBase != null)
                companyBrandLoaderProvider.overrideWithValue(
                  CompanyBrandLoader(_LocalLogoRepository()),
                ),
              if (_demoPrices)
                priceChartDataLoaderProvider.overrideWithValue(
                  _DemoPriceLoader(),
                ),
            ],
          );
          final theme = container.read(
            brightness == Brightness.light
                ? themeDataLightProvider
                : themeDataDarkProvider,
          );
          final components = parseExampleComponents(
            _swapText(item.exampleData[e]()),
          );
          final targets = componentsMatching(components, item.name).toList();
          final boundary = GlobalKey();
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme,
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: QaEvidenceScope(
                      lookup:
                          (_) => ValueNotifier(
                            TurnEvidence(calls: _evidenceFor(item.name)),
                          ),
                      child: RepaintBoundary(
                        key: boundary,
                        child: ColoredBox(
                          color: theme.extension<CustomColors>()!.background,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final component in targets)
                                  Builder(
                                    builder:
                                        (context) => item.widgetBuilder(
                                          catalogContextFor(
                                            buildContext: context,
                                            component: component,
                                            catalog: catalog,
                                          ),
                                        ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(
            () => Future<void>.delayed(
              Duration(milliseconds: _logoBase != null ? 1500 : 200),
            ),
          );
          await tester.pump(const Duration(seconds: 3));
          await tester.pump(const Duration(seconds: 3));
          if (_logoBase != null) {
            // Los logos se piden recién cuando el brand resolvió (en los
            // pumps de arriba): la descarga real necesita tiempo real.
            // Descarga y decodificación son trabajo real: se alternan esperas
            // reales con pumps hasta que el frame del logo esté listo.
            for (var i = 0; i < 6; i++) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 300)),
              );
              await tester.pump(const Duration(milliseconds: 400));
            }
          }
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image =
              (await tester.runAsync(() => render.toImage(pixelRatio: 2)))!;
          final bytes =
              (await tester.runAsync(
                () => image.toByteData(format: ui.ImageByteFormat.png),
              ))!;
          File('$_out/$name.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(bytes.buffer.asUint8List());
        }, skip: !_enabled);
      }
    }
  }
}
