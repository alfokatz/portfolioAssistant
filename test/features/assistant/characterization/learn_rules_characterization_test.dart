import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/routing/intent_router.dart';

import 'learn_rule_cases.dart';
import 'rules_contract.dart';

/// Caracterización de las reglas del modo Learn (`learnPromptRules`) y del
/// ruteo que hoy decide qué preguntas llegan a Learn — ver
/// `rules_contract.dart`.
void main() {
  String joinedFragments() => AssistantCatalog.buildFor(
    AssistantMode.learn,
  ).systemPromptFragments.join('\n');

  String rules() {
    final joined = joinedFragments();
    final start = joined.indexOf('LEARN MODE RULES');
    expect(start, isNonNegative);
    return joined.substring(start);
  }

  group('Learn rules — contract cases', () {
    verifyRuleCases(rules, learnRuleCases);
  });

  group('Learn rules — layout and bans', () {
    test('AnswerText always, TipBanner optional, nothing else', () {
      final selection = ruleSection(rules(), 'WIDGET SELECTION');
      expect(selection, contains('1. QaAnswerText (always required)'));
      expect(selection, contains('2. QaTipBanner (optional'));
      expect(selection, isNot(contains('3.')));
    });

    test('explicitly bans the numeric data widgets it knew about', () {
      final selection = ruleSection(rules(), 'WIDGET SELECTION');
      expect(
        selection,
        contains('NEVER use data widgets that display numbers:'),
      );
      for (final widget in const [
        'QaMetricStrip',
        'QaPeriodChange',
        'QaTickerMove',
        'QaPnLBreakdown',
        'QaConcentrationBar',
        'QaTopMovers',
        'QaPositionList',
        'QaClosedPositionList',
        'QaComparisonRow',
      ]) {
        expect(selection, contains(widget));
      }
    });

    test('no trading orders, answer capped at 2 short sentences', () {
      final style = ruleSection(rules(), 'RESPONSE STYLE');
      expect(style, contains('at most 2 short sentences'));
      expect(style, contains('No trading orders'));
    });

    test(
      'Learn gets portfolioContextPromptRules and the Learn-specific grounding rule',
      () {
        final joined = joinedFragments();
        expect(
          joined,
          contains('PORTFOLIO CONTEXT — DISPONIBLE EN TODOS LOS MODOS'),
        );
        expect(
          joined,
          contains(
            'Educational explanations (Learn mode) must not include specific live prices.',
          ),
        );
      },
    );
  });

  group('Learn rules — KNOWN GAPS (to be changed deliberately)', () {
    test('GAP-LN-1: the ban list omits widgets Learn never had in its catalog '
        '(incomplete once the catalog is unified)', () {
      final selection = ruleSection(rules(), 'WIDGET SELECTION');
      for (final widget in const [
        'QaTickerSnapshot',
        'QaPriceChart',
        'QaEarningsCalendar',
        'QaNewsSummary',
      ]) {
        expect(selection, isNot(contains(widget)));
      }
    });

    test('GAP-LN-2: a ticker price question that lands in Learn is told to ask '
        '"directly" — meaningless without modes', () {
      expect(
        ruleSection(rules(), 'DATA LIMITS'),
        contains('ask about that ticker directly'),
      );
    });
  });

  // Línea de base del ruteo actual. El pipeline unificado no tiene router
  // de modos, pero TIENE que igualar el resultado de ROUTE-1/ROUTE-2 (una
  // pregunta conceptual con un ticker de pasada sigue siendo conceptual) y
  // corregir ROUTE-BUG (el modo pegajoso que originó la decisión).
  group('Routing baseline (current pipeline)', () {
    AssistantMode route(String message, AssistantMode last) =>
        IntentRouter.detectEngine(message: message, lastEngine: last);

    test(
      'ROUTE-1: "¿qué es un ETF, como SPY?" goes to Learn from any engine',
      () {
        for (final last in [
          AssistantMode.portfolio,
          AssistantMode.explore,
          AssistantMode.learn,
        ]) {
          expect(
            route('¿Qué es un ETF, como SPY?', last),
            AssistantMode.learn,
            reason: 'from $last',
          );
        }
      },
    );

    test(
      'ROUTE-2: "¿qué es la diversificación?" goes to Learn from any engine',
      () {
        for (final last in [AssistantMode.portfolio, AssistantMode.explore]) {
          expect(
            route('¿Qué es la diversificación?', last),
            AssistantMode.learn,
          );
        }
      },
    );

    test('ROUTE-3: "¿cuál es el precio de AAPL?" reaches Explore', () {
      expect(
        route('¿Cuál es el precio de AAPL?', AssistantMode.learn),
        AssistantMode.explore,
      );
    });

    test('ROUTE-BUG (sticky mode): after a Learn turn, price questions without '
        'an explore keyword stay in Learn — the bug the unification fixes', () {
      for (final message in const [
        '¿A cuánto está AAPL?',
        '¿Cuánto vale AAPL?',
        '¿Cómo le fue a NVDA este mes?',
        '¿Por qué subió NVDA?',
      ]) {
        expect(
          route(message, AssistantMode.learn),
          AssistantMode.learn,
          reason: message,
        );
      }
    });
  });
}
