import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/reliability/grounding_prompt_rules.dart';

void main() {
  group('groundingPromptRules', () {
    test('contains anti-hallucination rules', () {
      expect(groundingPromptRules, contains('GROUNDING RULES'));
      expect(groundingPromptRules, contains('ASSISTANT_SNAPSHOT'));
      expect(groundingPromptRules, contains('Never invent tickers'));
    });
  });

  group('AssistantCatalog integration', () {
    for (final mode in AssistantMode.values) {
      test('$mode systemPromptFragments include grounding rules', () {
        final catalog = AssistantCatalog.buildFor(mode);
        final joined = catalog.systemPromptFragments.join('\n');

        expect(joined, contains('GROUNDING RULES — NEVER VIOLATE'));
        expect(joined, contains(groundingPromptRules.trim()));
      });
    }
  });
}
