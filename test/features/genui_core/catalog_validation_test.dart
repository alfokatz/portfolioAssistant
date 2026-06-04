import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:genui/test/validation.dart';
import 'package:portfolio_assistant/features/analysis/catalog/analysis_catalog.dart';
import 'package:portfolio_assistant/features/investment/catalog/investment_catalog.dart';
import 'package:portfolio_assistant/features/planning/catalog/planning_catalog.dart';

import '../../helpers/genui_test_helpers.dart';

void main() {
  Future<void> expectValidExamples(Catalog catalog, CatalogItem item) async {
    final errors = await validateCatalogItemExamples(item, catalog);
    expect(
      errors,
      isEmpty,
      reason: errors.map((e) => e.toString()).join('\n'),
    );
  }

  group('Analysis catalog schema validation', () {
    for (final name in analysisCustomComponentNames) {
      test('$name exampleData matches A2UI schema', () async {
        final catalog = AnalysisCatalog.build();
        final item = catalog.items.firstWhere((i) => i.name == name);
        await expectValidExamples(catalog, item);
      });
    }
  });

  group('Investment catalog schema validation', () {
    for (final name in investmentCustomComponentNames) {
      test('$name exampleData matches A2UI schema', () async {
        final catalog = InvestmentCatalog.build();
        final item = catalog.items.firstWhere((i) => i.name == name);
        await expectValidExamples(catalog, item);
      });
    }
  });

  group('Planning catalog schema validation', () {
    for (final name in planningCustomComponentNames) {
      test('$name exampleData matches A2UI schema', () async {
        final catalog = PlanningCatalog.build();
        final item = catalog.items.firstWhere((i) => i.name == name);
        await expectValidExamples(catalog, item);
      });
    }
  });
}
