import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_prompt_rules.dart';

import '../../../helpers/genui_test_helpers.dart';

// La decisión de "qué pregunta rutea a qué widget" la toma el modelo (ver
// explore_prompt_rules_test.dart para las reglas exactas que sigue). Esto
// verifica la capa determinística inmediatamente debajo de esa decisión:
// si el modelo elige QaEarningsCalendar / QaNewsSummary con el shape de
// datos que documenta el catálogo, el widget correcto se resuelve y
// renderiza sin caer al fallback de error.
void main() {
  group('QaEarningsCalendar / QaNewsSummary routing', () {
    final catalog = PortfolioQaCatalog.buildFor(
      AssistantMode.explore,
      explorePromptRules,
    );

    test('both widgets are reachable from the explore catalog', () {
      final names = catalog.items.map((item) => item.name).toSet();
      expect(names, contains('QaEarningsCalendar'));
      expect(names, contains('QaNewsSummary'));
    });

    testWidgets(
      'QaEarningsCalendar next-report example renders the report date',
      (tester) async {
        final item = catalog.items.firstWhere(
          (i) => i.name == 'QaEarningsCalendar',
        );

        await pumpCatalogItemExample(
          tester,
          catalog,
          item,
          exampleIndex: 0,
          surfaceId: 'explore_0',
        );

        expect(find.text('NVDA'), findsOneWidget);
        expect(find.text('13 nov 2026'), findsOneWidget);
      },
    );

    testWidgets(
      'QaEarningsCalendar latest-result example renders EPS actual vs. estimate',
      (tester) async {
        final item = catalog.items.firstWhere(
          (i) => i.name == 'QaEarningsCalendar',
        );

        await pumpCatalogItemExample(
          tester,
          catalog,
          item,
          exampleIndex: 1,
          surfaceId: 'explore_0',
        );

        expect(find.textContaining('3.30'), findsOneWidget);
        expect(find.textContaining('3.10'), findsOneWidget);
      },
    );

    testWidgets('QaNewsSummary example renders headlines with dates', (
      tester,
    ) async {
      final item = catalog.items.firstWhere((i) => i.name == 'QaNewsSummary');

      await pumpCatalogItemExample(
        tester,
        catalog,
        item,
        exampleIndex: 0,
        surfaceId: 'explore_0',
      );

      expect(
        find.textContaining('Apple supera expectativas'),
        findsOneWidget,
      );
      expect(find.textContaining('hace 2 días'), findsOneWidget);
    });
  });
}
