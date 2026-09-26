import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/prompts/portfolio_qa_system_prompt.dart';

import 'portfolio_rule_cases.dart';
import 'rules_contract.dart';

/// Caracterización de las reglas del modo Portfolio (`_portfolioQaRules`)
/// tal como están hoy, antes de la unificación de modos — ver
/// `rules_contract.dart`.
void main() {
  String joinedFragments() => AssistantCatalog.buildFor(
    AssistantMode.portfolio,
  ).systemPromptFragments.join('\n');

  String rules() {
    final joined = joinedFragments();
    final start = joined.indexOf('PORTFOLIO Q&A RULES');
    expect(start, isNonNegative);
    return joined.substring(start);
  }

  group('Portfolio rules — layout', () {
    test('AnswerText always, at most ONE data widget, optional TipBanner', () {
      final layout = ruleSection(rules(), 'LAYOUT');
      expect(layout, contains('1. QaAnswerText (always required)'));
      expect(layout, contains('2. At most ONE data widget'));
      expect(layout, contains('3. QaTipBanner (optional'));
    });

    test(
      'QaAnswerText is capped at 2 short sentences, never repeats widget numbers',
      () {
        final style = ruleSection(rules(), 'RESPONSE STYLE');
        expect(style, contains('at most 2 short sentences'));
        expect(
          style,
          contains('Never repeat numbers that appear in a widget below.'),
        );
      },
    );
  });

  group('Portfolio rules — contract cases', () {
    verifyRuleCases(rules, portfolioRuleCases);
  });

  // KNOWN GAPS: comportamiento actual que la unificación va a cambiar A
  // PROPÓSITO (decisión del 2026-09-25). Se fijan acá para que el cambio
  // sea un test que hay que actualizar explícitamente, no una deriva.
  group('Portfolio rules — KNOWN GAPS (to be changed deliberately)', () {
    test('GAP-PF-1: "¿qué posiciones tengo?" matches two guide lines with no '
        'tie-break (QaMetricStrip vs QaPositionList) — decision: rename the '
        'Portfolio snapshot widget apart from QaMetricStrip', () {
      final guide = ruleSection(rules(), 'WIDGET SELECTION GUIDE');
      expect(
        guide,
        contains('Current snapshot / open positions: QaMetricStrip'),
      );
      expect(guide, contains('List open positions: QaPositionList'));
      expect(guide, isNot(contains('first match wins')));
    });

    test('GAP-PF-2: a single ticker WITHOUT a period ("¿cómo va mi AAPL?") has '
        'no rule at all in Portfolio', () {
      final r = rules();
      expect(r, isNot(contains('QaTickerSnapshot')));
      expect(r, isNot(contains('QaPriceChart')));
      expect(r, isNot(contains('no time window')));
    });

    test('GAP-PF-3: WHY says there are no news — contradicts Explore (Finnhub '
        'news). Decision: news iff plan allows AND news available', () {
      final why = ruleSection(rules(), 'WHY / CAUSATION QUESTIONS');
      expect(why, contains('You have NO verified news'));
      expect(
        why,
        contains(
          'causes require external\n  news sources not available in this chat yet',
        ),
      );
      expect(why, isNot(contains('news_enrichment')));
    });

    test(
      'GAP-PF-4: Portfolio is the only mode WITHOUT portfolioContextPromptRules '
      '(it reads portfolio fields at the snapshot root, not under '
      'portfolio_context)',
      () {
        expect(
          joinedFragments(),
          isNot(contains('PORTFOLIO CONTEXT — DISPONIBLE')),
        );
        expect(rules(), contains('Use ONLY data from PORTFOLIO_SNAPSHOT'));
      },
    );

    test(
      'GAP-PF-5: snapshot naming is inconsistent — the user message says '
      'PORTFOLIO_SNAPSHOT, the shared grounding rules say ASSISTANT_SNAPSHOT',
      () {
        final body = portfolioQaUserMessageBody(
          portfolioSnapshotJson: '{}',
          question: 'q',
          surfaceId: 's',
        );
        expect(body, contains('PORTFOLIO_SNAPSHOT'));
        expect(joinedFragments(), contains('ASSISTANT_SNAPSHOT'));
      },
    );
  });
}
