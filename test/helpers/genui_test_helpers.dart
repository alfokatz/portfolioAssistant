import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/shared/widgets/genui_error_card.dart';

typedef JsonMap = Map<String, dynamic>;

/// Viewport típico de teléfono para smoke tests de catálogo GenUI.
const genuiTestViewportSize = Size(390, 844);

/// Nombres de componentes custom del flujo de análisis.
const analysisCustomComponentNames = {
  'PortfolioSummaryCard',
  'AssetPerformanceCard',
  'AlertBanner',
  'PortfolioInsightCard',
  'NewsHighlightCard',
  'NewsFeedCard',
  'QuickActionRow',
};

/// Nombres de componentes custom del flujo de inversión.
const investmentCustomComponentNames = {
  'InvestmentOpportunityCard',
  'RiskProfileSlider',
  'BudgetAllocationCard',
  'MarketContextCard',
  'InvestmentConfirmCard',
  'AlertBanner',
};

/// Nombres de componentes custom del flujo de planificación.
const planningCustomComponentNames = {
  'GoalCard',
  'ProjectionChart',
  'MilestoneTimeline',
  'ActionPriorityCard',
  'GapAnalysisCard',
};

List<JsonMap> parseExampleComponents(String exampleJson) {
  final decoded = jsonDecode(exampleJson.trim()) as List<dynamic>;
  return decoded.cast<JsonMap>();
}

Iterable<JsonMap> componentsMatching(
  List<JsonMap> components,
  String componentName,
) {
  return components.where((c) => c['component'] == componentName);
}

CatalogItemContext catalogContextFor({
  required BuildContext buildContext,
  required JsonMap component,
  required Catalog catalog,
  String surfaceId = 'test_surface',
}) {
  return CatalogItemContext(
    id: component['id'] as String? ?? 'root',
    type: component['component'] as String,
    data: component,
    buildChild: (_, [__]) => const SizedBox.shrink(),
    dispatchEvent: (_) {},
    buildContext: buildContext,
    dataContext: DataContext(InMemoryDataModel(), DataPath.root),
    getComponent: (_) => null,
    getCatalogItem: (type) {
      for (final item in catalog.items) {
        if (item.name == type) return item;
      }
      return null;
    },
    surfaceId: surfaceId,
    reportError: (_, __) {},
  );
}

/// Aplica líneas JSON A2UI (post-normalizer) al [controller].
void dispatchNormalizedA2ui(SurfaceController controller, String normalized) {
  for (final line in normalized.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final map = jsonDecode(trimmed) as JsonMap;
    controller.handleMessage(A2uiMessage.fromJson(map));
  }
}

String loadGenuiFixture(String fileName) {
  return File('test/fixtures/genui/$fileName').readAsStringSync();
}

ThemeData genuiTestTheme() {
  const customColors = CustomColors(
    profit: PortfolioColors.profit,
    loss: PortfolioColors.loss,
    profitContainer: Color(0xFF14532D),
    lossContainer: Color(0xFF3D1515),
    chartGrid: PortfolioColors.chartGrid,
    accentBlue: PortfolioColors.accentBlue,
    cardBackground: PortfolioColors.surfaceCard,
    aiCardBorder: Color(0xFF3B82F6),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: PortfolioColors.background,
    extensions: [customColors],
  );
}

Widget genuiTestApp({required Widget child}) {
  return MaterialApp(
    theme: genuiTestTheme(),
    home: Scaffold(body: child),
  );
}

Future<void> pumpCatalogItemExample(
  WidgetTester tester,
  Catalog catalog,
  CatalogItem item, {
  int exampleIndex = 0,
  String surfaceId = 'test_surface',
}) async {
  final components = parseExampleComponents(item.exampleData[exampleIndex]());
  final targets = componentsMatching(components, item.name).toList();
  expect(
    targets,
    isNotEmpty,
    reason: '${item.name} example $exampleIndex must include that component',
  );

  await tester.binding.setSurfaceSize(genuiTestViewportSize);

  await tester.pumpWidget(
    genuiTestApp(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
              for (final component in targets)
                Builder(
                  key: ValueKey('${item.name}_${component['id']}'),
                  builder: (context) {
                    return item.widgetBuilder!(
                      catalogContextFor(
                        buildContext: context,
                        component: component,
                        catalog: catalog,
                        surfaceId: surfaceId,
                      ),
                    );
                  },
                ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();

  expect(
    find.byType(GenUiErrorCard),
    findsNothing,
    reason: '${item.name} example $exampleIndex should not render error fallback',
  );
}

List<CatalogItem> customCatalogItems(
  Catalog catalog,
  Set<String> names,
) {
  return catalog.items.where((item) => names.contains(item.name)).toList();
}
