import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_assistant_catalog.dart';

import '../../../helpers/genui_test_helpers.dart';

void main() {
  final catalog = UnifiedAssistantCatalog.build();
  Set<String> qaNames() =>
      catalog.items.map((i) => i.name).where((n) => n.startsWith('Qa')).toSet();

  test(
    'exactly the 16 approved widgets: Portfolio + Learn + Explore, no Invest/Plan',
    () {
      expect(qaNames(), UnifiedAssistantCatalog.widgetNames);
      expect(qaNames(), hasLength(16));
      for (final investOrPlan in const [
        'QaBudgetSplit',
        'QaInvestOption',
        'QaInvestConfirm',
        'QaGoalCard',
        'QaProjectionStrip',
        'QaProjectionChart',
        'QaMilestoneList',
      ]) {
        expect(qaNames(), isNot(contains(investOrPlan)));
      }
    },
  );

  test('no mode language or legacy snapshot keys leak into the prompt', () {
    final prompt = [
      ...catalog.systemPromptFragments,
      for (final item in catalog.items) item.dataSchema.toJson(),
    ].join('\n');
    for (final leak in const [
      'modo explore',
      'portfolio mode',
      'explore mode',
      'Learn mode',
      'explore_tickers',
      'portfolio_context',
      'PORTFOLIO_SNAPSHOT',
    ]) {
      expect(prompt, isNot(contains(leak)), reason: leak);
    }
  });

  test(
    'QaMetricStrip keeps only the comparison meaning; QaPositionsSnapshot owns the portfolio one',
    () {
      String description(String name) =>
          catalog.items
              .firstWhere((i) => i.name == name)
              .dataSchema
              .description!;
      expect(description('QaMetricStrip'), contains('Compara 2-3 tickers'));
      expect(description('QaMetricStrip'), isNot(contains('valor/P&L')));
      expect(
        description('QaPositionsSnapshot'),
        contains('TUS posiciones abiertas'),
      );
    },
  );

  group(
    'every widget renders its example without falling back to the error card',
    () {
      for (final item in UnifiedAssistantCatalog.items) {
        for (var i = 0; i < item.exampleData.length; i++) {
          testWidgets('${item.name} example $i', (tester) async {
            await pumpCatalogItemExample(
              tester,
              catalog,
              item,
              exampleIndex: i,
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.textContaining('No pude'), findsNothing);
            expect(find.byType(ErrorWidget), findsNothing);
          });
        }
      }
    },
  );
}
