import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_prompt_rules.dart';

void main() {
  group('explorePromptRules', () {
    // Regresión: explore era el modo con la guía más floja para decidir
    // texto-vs-widget (no tenía una regla explícita, a diferencia de
    // portfolio/invest/plan/learn) — esto suma una sección positiva
    // explícita, en la misma línea que el resto.
    test('has an explicit text-vs-widget decision rule', () {
      expect(explorePromptRules, contains('WHEN TO USE PLAIN TEXT VS. A WIDGET'));
      expect(explorePromptRules, contains('QaAnswerText only'));
    });
  });

  group('AssistantCatalog integration', () {
    test('explore mode systemPromptFragments include the decision rule', () {
      final catalog = AssistantCatalog.buildFor(AssistantMode.explore);
      final joined = catalog.systemPromptFragments.join('\n');

      expect(joined, contains('WHEN TO USE PLAIN TEXT VS. A WIDGET'));
    });
  });
}
