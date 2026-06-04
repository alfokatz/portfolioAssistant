import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/analysis/catalog/analysis_catalog.dart';
import 'package:portfolio_assistant/features/investment/catalog/investment_catalog.dart';
import 'package:portfolio_assistant/features/planning/catalog/planning_catalog.dart';

import '../../helpers/genui_test_helpers.dart';

void main() {
  group('Analysis catalog widget smoke', () {
    testWidgets('custom components render without GenUiErrorCard', (
      WidgetTester tester,
    ) async {
      final catalog = AnalysisCatalog.build();
      final items = customCatalogItems(catalog, analysisCustomComponentNames);

      for (final item in items) {
        for (var i = 0; i < item.exampleData.length; i++) {
          await pumpCatalogItemExample(
            tester,
            catalog,
            item,
            exampleIndex: i,
            surfaceId: 'portfolio_analysis',
          );
        }
      }
    });
  });

  group('Investment catalog widget smoke', () {
    testWidgets('custom components render without GenUiErrorCard', (
      WidgetTester tester,
    ) async {
      final catalog = InvestmentCatalog.build();
      final items = customCatalogItems(catalog, investmentCustomComponentNames);

      for (final item in items) {
        for (var i = 0; i < item.exampleData.length; i++) {
          await pumpCatalogItemExample(
            tester,
            catalog,
            item,
            exampleIndex: i,
            surfaceId: 'investment_decision',
          );
        }
      }
    });
  });

  group('Planning catalog widget smoke', () {
    testWidgets('custom components render without GenUiErrorCard', (
      WidgetTester tester,
    ) async {
      final catalog = PlanningCatalog.build();
      final items = customCatalogItems(catalog, planningCustomComponentNames);

      for (final item in items) {
        for (var i = 0; i < item.exampleData.length; i++) {
          await pumpCatalogItemExample(
            tester,
            catalog,
            item,
            exampleIndex: i,
            surfaceId: 'long_term_planning',
          );
        }
      }
    });
  });
}
