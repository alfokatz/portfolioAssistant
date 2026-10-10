// Screenshots de cada widget del catálogo GenUI (el ejemplo de cada
// CatalogItem), con fuentes reales y el tema claro de la app. No corre en la
// suite normal (escribe PNGs):
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
//     flutter test test/screenshots/genui_catalog_screenshots_test.dart
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
          final container = ProviderContainer();
          final theme = container.read(
            brightness == Brightness.light
                ? themeDataLightProvider
                : themeDataDarkProvider,
          );
          final components = parseExampleComponents(item.exampleData[e]());
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
                            TurnEvidence(
                              calls: _evidence[item.name] ?? const [],
                            ),
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
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pump(const Duration(seconds: 3));
          await tester.pump(const Duration(seconds: 3));
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
