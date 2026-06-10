import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_prompt_rules.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';

void main() {
  group('explorePromptRules', () {
    test('contains anti-hallucination rules for empty news_sources', () {
      expect(explorePromptRules, contains('NEWS / CAUSATION'));
      expect(explorePromptRules, contains('news_enrichment is "empty"'));
      expect(explorePromptRules, contains('do NOT speculate on causes'));
      expect(
        explorePromptRules,
        contains('NEVER invent event names'),
      );
    });

    test('contains broad market proxy rules', () {
      expect(explorePromptRules, contains('BROAD MARKET QUESTIONS'));
      expect(explorePromptRules, contains('market_proxy_ticker'));
      expect(
        explorePromptRules,
        contains('Do NOT claim an unrelated ticker represents'),
      );
    });

    test('requires citing only news_sources when present', () {
      expect(explorePromptRules, contains('news_enrichment is "ok"'));
      expect(
        explorePromptRules,
        contains('news_sources[].{title, url, snippet}'),
      );
      expect(explorePromptRules, contains('never invent events'));
      expect(explorePromptRules, contains('Mention source titles'));
    });
  });

  group('AssistantCatalog integration', () {
    test('explore catalog includes explore news rules', () {
      final catalog = AssistantCatalog.buildFor(AssistantMode.explore);
      final joined = catalog.systemPromptFragments.join('\n');

      expect(joined, contains('NEWS / CAUSATION'));
      expect(joined, contains(explorePromptRules.trim()));
      expect(joined, contains('never invent events'));
      expect(joined, contains('do NOT speculate on causes'));
    });
  });
}
