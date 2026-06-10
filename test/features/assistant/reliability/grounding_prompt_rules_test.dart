import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog.dart';
import 'package:portfolio_assistant/features/assistant/reliability/grounding_prompt_rules.dart';

void main() {
  group('groundingPromptRules', () {
    test('contains anti-hallucination rules', () {
      expect(groundingPromptRules, contains('GROUNDING RULES'));
      expect(groundingPromptRules, contains('ASSISTANT_SNAPSHOT'));
      expect(groundingPromptRules, contains('Never invent tickers'));
    });
  });

  group('PortfolioQaCatalog integration', () {
    test('systemPromptFragments include grounding rules', () {
      final catalog = PortfolioQaCatalog.build();
      final joined = catalog.systemPromptFragments.join('\n');

      expect(joined, contains('GROUNDING RULES — NEVER VIOLATE'));
      expect(joined, contains(groundingPromptRules.trim()));
    });
  });
}
