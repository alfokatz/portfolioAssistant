import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_prompt_rules.dart';

import '../characterization/learn_rule_cases.dart';
import '../characterization/portfolio_rule_cases.dart';
import '../characterization/rules_contract.dart';

/// Suite unificada — migración de los casos contrato de Portfolio y Learn
/// (mismos ids que `characterization/`), más los casos nuevos de la
/// decisión del 2026-09-25 (C1–C6, B1–B6) y adversariales cruzados.
///
/// Un caso marcado `CHANGED` cambia su widget o su fuente A PROPÓSITO, por
/// una decisión explícita; todos los demás prescriben lo mismo que antes.
void main() {
  String rules() => unifiedPromptRules;

  // --- Migración 1:1 de Portfolio + Learn --------------------------------
  const migrated = <RuleCase>[
    // Temporal (cartera completa): sin cambios.
    RuleCase(
      id: 'PF-TEMP-DAY',
      question: '¿cómo le fue a mi portfolio hoy?',
      section: 'TEMPORAL QUESTIONS',
      expectedWidgets: ['QaPeriodChange'],
      anchors: [
        '"hoy", "último día" → period_returns.day',
        'use QaPeriodChange',
      ],
    ),
    RuleCase(
      id: 'PF-TEMP-WEEK',
      question: '¿cómo le fue a mi portfolio esta semana?',
      section: 'TEMPORAL QUESTIONS',
      expectedWidgets: ['QaPeriodChange'],
      anchors: [
        '"esta semana", "últimos 7 días", "semanal" → period_returns.week',
      ],
    ),
    RuleCase(
      id: 'PF-TEMP-MONTH',
      question: '¿cómo vino mi cartera este mes?',
      section: 'TEMPORAL QUESTIONS',
      expectedWidgets: ['QaPeriodChange'],
      anchors: ['"este mes", "último mes", "mensual" → period_returns.month'],
    ),
    RuleCase(
      id: 'PF-TEMP-QUARTER',
      question: '¿cómo le fue a mi portfolio en el trimestre?',
      section: 'TEMPORAL QUESTIONS',
      expectedWidgets: ['QaPeriodChange'],
      anchors: ['"trimestre", "últimos 3 meses" → period_returns.quarter'],
    ),
    RuleCase(
      id: 'PF-TEMP-YEAR',
      question: '¿cómo le fue a mi portfolio este año?',
      section: 'TEMPORAL QUESTIONS',
      expectedWidgets: ['QaPeriodChange'],
      anchors: ['"este año", "anual" → period_returns.year'],
    ),
    RuleCase(
      id: 'PF-TEMP-NOT-ALLTIME',
      question: '¿cuánto gané esta semana?',
      section: 'TEMPORAL QUESTIONS',
      expectedWidgets: ['QaPeriodChange'],
      anchors: [
        'NEVER use total_pnl_abs or QaPnLBreakdown for "esta semana" or similar.',
        'total_pnl_abs / total_pnl_pct = ALL-TIME since purchase',
      ],
    ),
    RuleCase(
      id: 'PF-TEMP-NO-HISTORY',
      question: '¿cómo le fue a mi portfolio este año? (sin historial)',
      section: 'TEMPORAL QUESTIONS',
      expectedWidgets: [],
      anchors: [
        'If has_sufficient_history is false for the requested period, say so in\nQaAnswerText and omit the data widget.',
      ],
    ),
    // Ticker de la cartera + período: mismo widget, ahora explícitamente
    // condicionado a tenencia (decisión 4).
    RuleCase(
      id: 'PF-TICKER-PERIOD',
      question: '¿cómo fue AAPL esta semana? (la tiene)',
      section: 'HELD TICKER + EXPLICIT PERIOD',
      expectedWidgets: ['QaTickerMove'],
      anchors: [
        '"¿cómo fue AAPL esta semana?" → portfolio.position_periods.AAPL.week + QaTickerMove',
        'weightPct from\n  portfolio.positions[]',
      ],
    ),
    // CHANGED (decisión 4): "¿por qué?" ya no niega noticias — depende de
    // access.news / news_enrichment. El widget de movimiento se mantiene.
    RuleCase(
      id: 'PF-WHY-TICKER',
      question: '¿por qué cayó NVDA?',
      section: 'WHY / CAUSATION',
      expectedWidgets: ['QaTickerMove', 'QaPriceChart', 'QaTipBanner'],
      anchors: [
        'Whether causes may be cited depends ONLY on access.news and\nnews_enrichment — not on whether the user holds the ticker.',
        'NEVER invent causes, earnings, macro events, or news headlines.',
      ],
    ),
    RuleCase(
      id: 'PF-WHY-PORTFOLIO',
      question: '¿por qué bajó mi portfolio?',
      section: 'WHY / CAUSATION',
      expectedWidgets: ['QaPeriodChange', 'QaTipBanner'],
      anchors: [
        '"¿por qué bajó mi portfolio?"',
        'for the whole portfolio,\nQaPeriodChange',
      ],
    ),
    // Posiciones cerradas: sin cambios.
    RuleCase(
      id: 'PF-CLOSED-TOTAL',
      question: '¿cuánto gané en total con lo que cerré?',
      section: 'CLOSED POSITIONS',
      expectedWidgets: ['QaPnLBreakdown'],
      anchors: [
        '"cuánto gané en total cerrado": QaPnLBreakdown with costBasis =\n  closed_pnl_total_cost_basis',
      ],
    ),
    RuleCase(
      id: 'PF-CLOSED-BEST-WORST',
      question: '¿cuál fue mi mejor operación cerrada?',
      section: 'BEST / WORST',
      expectedWidgets: ['QaTopMovers'],
      anchors: ['QaTopMovers with pnlPct from portfolio.closed_positions[]'],
    ),
    RuleCase(
      id: 'PF-CLOSED-LIST',
      question: 'listame mis posiciones cerradas',
      section: 'CLOSED POSITIONS',
      expectedWidgets: ['QaClosedPositionList'],
      anchors: [
        '"listar posiciones cerradas": QaClosedPositionList (max 6 items, most recent)',
      ],
    ),
    RuleCase(
      id: 'PF-CLOSED-COMPARE',
      question: 'comparame lo que gané con TSLA y con AMD (cerradas)',
      section: 'CLOSED POSITIONS',
      expectedWidgets: ['QaComparisonRow'],
      anchors: [
        'Compare two closed tickers: QaComparisonRow using pnl_pct or pnl_abs',
      ],
    ),
    RuleCase(
      id: 'PF-CLOSED-NO-MIX',
      question: '¿cuánto gané en total? (con abiertas y cerradas)',
      section: 'CLOSED POSITIONS',
      expectedWidgets: [],
      anchors: [
        'NEVER mix closed realized P&L with open unrealized total_pnl_*',
        'If has_positions is false but has_closed_positions is true, the user has\n  NO open positions',
      ],
    ),
    // CHANGED (decisión 4, rename): la foto de posiciones ya no es
    // QaMetricStrip sino QaPositionsSnapshot.
    RuleCase(
      id: 'PF-GUIDE-SNAPSHOT',
      question: '¿cómo está mi cartera ahora?',
      section: 'YOUR PORTFOLIO — CURRENT STATE',
      expectedWidgets: ['QaPositionsSnapshot'],
      anchors: [
        '"¿cómo está mi cartera?"',
        'QaPositionsSnapshot with totalValue =\n  total_value',
      ],
    ),
    RuleCase(
      id: 'PF-GUIDE-ALLTIME',
      question: '¿cuánto gané desde que compré todo?',
      section: 'YOUR PORTFOLIO — CURRENT STATE',
      expectedWidgets: ['QaPnLBreakdown'],
      anchors: ['QaPnLBreakdown from total_cost_basis / total_value'],
    ),
    RuleCase(
      id: 'PF-GUIDE-RISK',
      question: '¿qué tan concentrada está mi cartera?',
      section: 'YOUR PORTFOLIO — CURRENT STATE',
      expectedWidgets: ['QaConcentrationBar'],
      anchors: ['"¿qué tan concentrada está mi cartera?"'],
    ),
    RuleCase(
      id: 'PF-GUIDE-BEST-WORST-OPEN',
      question: '¿cuáles son mis mejores y peores posiciones?',
      section: 'BEST / WORST',
      expectedWidgets: ['QaTopMovers'],
      anchors: ['QaTopMovers with pnlPct from\n  portfolio.positions[]'],
    ),
    RuleCase(
      id: 'PF-GUIDE-LIST-OPEN',
      question: 'listame mis posiciones',
      section: 'YOUR PORTFOLIO — CURRENT STATE',
      expectedWidgets: ['QaPositionList'],
      anchors: ['"listame mis posiciones"'],
    ),
    // Mismo widget; ahora es el caso C4 (ambos en cartera, sin métrica).
    RuleCase(
      id: 'PF-GUIDE-COMPARE',
      question: 'comparame AAPL y MSFT (tiene las dos)',
      section: 'COMPARING 2-3 TICKERS',
      expectedWidgets: ['QaComparisonRow'],
      anchors: [
        'C4. TWO tickers, NO metric stated ("comparame AAPL y MSFT"), both held →\n  QaComparisonRow',
      ],
    ),
    RuleCase(
      id: 'PF-GUIDE-CONCEPT',
      question: '¿qué es la diversificación?',
      section: 'STEP 0 — CONCEPTUAL QUESTIONS',
      expectedWidgets: ['QaAnswerText'],
      anchors: ['QaAnswerText only, or QaAnswerText + QaTipBanner'],
    ),
    // Learn.
    RuleCase(
      id: 'LN-CONCEPT',
      question: '¿qué es diversificar?',
      section: 'STEP 0 — CONCEPTUAL QUESTIONS',
      expectedWidgets: ['QaAnswerText'],
      anchors: ['NEVER a data widget.'],
    ),
    RuleCase(
      id: 'LN-CONCEPT-TAKEAWAY',
      question: '¿qué es el interés compuesto y cómo lo aprovecho?',
      section: 'STEP 0 — CONCEPTUAL QUESTIONS',
      expectedWidgets: ['QaAnswerText', 'QaTipBanner'],
      anchors: [
        'QaAnswerText + QaTipBanner when a practical\n  takeaway adds value',
      ],
    ),
    RuleCase(
      id: 'LN-CONCEPT-NO-RANDOM-TICKERS',
      question: '¿qué es un ETF?',
      section: 'STEP 0 — CONCEPTUAL QUESTIONS',
      expectedWidgets: [],
      anchors: [
        'Explain with generic examples only — never live prices in a conceptual\n  answer.',
      ],
    ),
    // CHANGED: ya no hay que "responder en texto desde Learn" — una
    // pregunta sobre su cartera va al ranking con sus datos reales.
    RuleCase(
      id: 'LN-OWN-PORTFOLIO',
      question: '¿qué es lo que tiene más riesgo en mi portfolio?',
      section: 'YOUR PORTFOLIO — CURRENT STATE',
      expectedWidgets: ['QaConcentrationBar'],
      anchors: [
        '"¿qué es\n  lo que tiene más riesgo en mi portfolio?") → QaConcentrationBar',
      ],
    ),
    // CHANGED (GAP-LN-2): ya no se le pide al usuario que "pregunte
    // directo" — el precio de un ticker es QaPriceChart en cualquier turno.
    RuleCase(
      id: 'LN-TICKER-PRICE',
      question: '¿a cuánto está NVDA?',
      section: 'PRICE / EVOLUTION OF ONE TICKER',
      expectedWidgets: ['QaPriceChart'],
      anchors: ['"¿a cuánto está AAPL?"', 'QaPriceChart WINS BY DEFAULT'],
    ),
  ];

  group('migrated Portfolio + Learn contract cases', () {
    test('every characterization id has a unified counterpart', () {
      final migratedIds = migrated.map((c) => c.id).toSet();
      final expected = {
        ...portfolioRuleCases.map((c) => c.id),
        ...learnRuleCases.map((c) => c.id),
      };
      expect(migratedIds.difference(expected), isEmpty, reason: 'unknown ids');
      expect(
        expected.difference(migratedIds),
        isEmpty,
        reason: 'ids not migrated',
      );
    });

    verifyRuleCases(rules, migrated);
  });

  // --- KNOWN GAPS de la caracterización, ahora revertidos a propósito ------
  group('known gaps are closed', () {
    test(
      'GAP-PF-1: "which holdings" vs "totals" has an explicit tie-break',
      () {
        final state = ruleSection(rules(), 'YOUR PORTFOLIO — CURRENT STATE');
        expect(state, contains('First match wins:'));
        expect(state, contains('(asks WHICH holdings) →\n  QaPositionList'));
        expect(state, contains('(asks for TOTALS) → QaPositionsSnapshot'));
        expect(state, isNot(contains('QaMetricStrip for')));
      },
    );

    test(
      'GAP-PF-2: a held ticker WITHOUT a window has a rule (QaPriceChart)',
      () {
        expect(
          ruleSection(rules(), 'HELD TICKER + EXPLICIT PERIOD'),
          contains(
            'A held ticker WITHOUT a time window ("¿cómo va mi AAPL?") is step 8:\n  QaPriceChart.',
          ),
        );
      },
    );

    test('GAP-PF-3: WHY no longer claims there are no news in this chat', () {
      expect(rules(), isNot(contains('You have NO verified news')));
      expect(rules(), isNot(contains('not available in this chat yet')));
    });

    test(
      'GAP-PF-4: one snapshot shape — portfolio data always under portfolio.*',
      () {
        expect(rules(), contains('portfolio.period_returns'));
        expect(rules(), contains('portfolio.position_periods'));
        expect(rules(), isNot(contains('portfolio_context')));
        expect(rules(), isNot(contains('explore_tickers')));
      },
    );

    test('GAP-PF-5: one snapshot name — ASSISTANT_SNAPSHOT', () {
      expect(rules(), contains('ASSISTANT_SNAPSHOT'));
      expect(rules(), isNot(contains('PORTFOLIO_SNAPSHOT')));
    });

    test(
      'GAP-LN-1: conceptual answers ban EVERY data widget, including the new ones',
      () {
        final step0 = ruleSection(rules(), 'STEP 0 — CONCEPTUAL QUESTIONS');
        for (final widget in const [
          'QaTickerSnapshot',
          'QaTickerMove',
          'QaPriceChart',
          'QaMetricStrip',
        ]) {
          expect(step0, contains(widget));
        }
        expect(step0, contains('or any other\n  data widget'));
      },
    );

    test('GAP-LN-2: nobody is told to "ask directly" anymore', () {
      expect(rules(), isNot(contains('ask about that ticker directly')));
    });

    test('no rule references a mode', () {
      for (final word in const [
        'MODE RULES',
        'Learn mode',
        'modo explore',
        'portfolio mode',
      ]) {
        expect(rules(), isNot(contains(word)));
      }
    });
  });

  // --- Decisión 4: comparaciones y mejor/peor (aprobadas) ------------------
  group('comparisons (C1–C6)', () {
    verifyRuleCases(rules, const [
      RuleCase(
        id: 'C1',
        question: '¿cómo vienen NVDA, AMD y AAPL?',
        section: 'COMPARING 2-3 TICKERS',
        expectedWidgets: ['QaMetricStrip'],
        anchors: [
          'C1. THREE tickers ("¿cómo vienen NVDA, AMD y AAPL?") → QaMetricStrip.',
        ],
      ),
      RuleCase(
        id: 'C2',
        question: '¿con cuál gané más, AAPL o MSFT? (tiene las dos)',
        section: 'COMPARING 2-3 TICKERS',
        expectedWidgets: ['QaComparisonRow'],
        anchors: [
          'C2. TWO tickers + the user\'s OWN RESULT',
          'metricLabel "Rendimiento en tu cartera"',
        ],
      ),
      RuleCase(
        id: 'C3',
        question: '¿cuál subió más esta semana, NVDA o AMD?',
        section: 'COMPARING 2-3 TICKERS',
        expectedWidgets: ['QaMetricStrip'],
        anchors: [
          'C3. TWO tickers + a PRICE MOVE in a window',
          'held or not → QaMetricStrip.',
        ],
      ),
      RuleCase(
        id: 'C4',
        question: 'comparame AAPL y MSFT (tiene las dos)',
        section: 'COMPARING 2-3 TICKERS',
        expectedWidgets: ['QaComparisonRow'],
        anchors: ['C4. TWO tickers, NO metric stated'],
      ),
      RuleCase(
        id: 'C5',
        question: 'comparame AAPL y TSLA (no tiene TSLA)',
        section: 'COMPARING 2-3 TICKERS',
        expectedWidgets: ['QaMetricStrip'],
        anchors: [
          'C5. TWO tickers, NO metric stated, at least one NOT held',
          'QaMetricStrip with the day change.',
        ],
      ),
      RuleCase(
        id: 'C6',
        question: '¿con cuál gané más, AAPL o TSLA? (no tiene TSLA)',
        section: 'COMPARING 2-3 TICKERS',
        expectedWidgets: ['QaMetricStrip'],
        anchors: [
          'C6. Like C2 but one of the two is NOT held',
          "say in\n  QaAnswerText that they don't hold the other one.",
        ],
      ),
    ]);

    test('the tie-break is the metric; holding only picks the data source', () {
      final comparing = ruleSection(rules(), 'COMPARING 2-3 TICKERS');
      expect(comparing, contains('The tie-break is the METRIC'));
      expect(
        comparing,
        contains('holding only decides where the numbers come from'),
      );
    });
  });

  group('best / worst (B1–B6)', () {
    verifyRuleCases(rules, const [
      RuleCase(
        id: 'B1',
        question: '¿qué me fue mejor, AAPL o MSFT?',
        section: 'BEST / WORST',
        expectedWidgets: ['QaComparisonRow'],
        anchors: ['B1. A NAMED PAIR', 'Never QaTopMovers for a named pair.'],
      ),
      RuleCase(
        id: 'B2',
        question: '¿cuál es mi peor posición?',
        section: 'BEST / WORST',
        expectedWidgets: ['QaTopMovers'],
        anchors: ['B2. Superlative over their OPEN positions, all-time'],
      ),
      RuleCase(
        id: 'B3',
        question: 'mi mejor operación cerrada',
        section: 'BEST / WORST',
        expectedWidgets: ['QaTopMovers'],
        anchors: ['B3. Superlative over CLOSED trades'],
      ),
      RuleCase(
        id: 'B4',
        question: '¿cuál de mis acciones subió más esta semana?',
        section: 'BEST / WORST',
        expectedWidgets: ['QaTopMovers'],
        anchors: [
          'QaTopMovers with changePct from\n  portfolio.position_periods.{TICKER}.{period}.change_pct and periodLabel',
          'Never put a period change in pnlPct (pnlPct is all-time\n  P&L).',
        ],
      ),
      RuleCase(
        id: 'B5',
        question: '¿qué acción subió más hoy?',
        section: 'BEST / WORST',
        expectedWidgets: ['QaAnswerText'],
        anchors: [
          'B5. Superlative over the WHOLE MARKET',
          'there is no market-wide data',
        ],
      ),
      RuleCase(
        id: 'B6',
        question: '¿cuál es mi mejor posición? (tiene una sola)',
        section: 'BEST / WORST',
        expectedWidgets: ['QaAnswerText'],
        anchors: ['B6. Only ONE open position'],
      ),
    ]);
  });

  // --- Adversariales cruzados: widgets parecidos que ahora conviven -------
  group('adversarial cross cases', () {
    test(
      '"¿qué es un ETF, como SPY?" is conceptual → QaAnswerText, never a ticker widget',
      () {
        final step0 = ruleSection(rules(), 'STEP 0 — CONCEPTUAL QUESTIONS');
        expect(step0, contains('"¿qué es un\n  ETF, como SPY?"'));
        expect(
          step0,
          contains(
            'a ticker used as\n  an example is not a request for its data',
          ),
        );
        expect(
          step0,
          contains('even if tickers.{TICKER} happens to be present'),
        );
      },
    );

    test('STEP 0 is checked before any ticker or portfolio rule', () {
      final ranking = ruleSection(rules(), 'WIDGET SELECTION GUIDE — RANKING');
      final conceptual = ranking.indexOf('1. Conceptual question');
      expect(conceptual, isNonNegative);
      for (final widget in const [
        'QaPriceChart',
        'QaTickerMove',
        'QaTickerSnapshot',
        'QaMetricStrip',
        'QaEarningsCalendar',
        'QaNewsSummary',
      ]) {
        expect(conceptual, lessThan(ranking.indexOf(widget)), reason: widget);
      }
    });

    test('"qué es" about their OWN data is NOT conceptual', () {
      expect(
        ruleSection(rules(), 'STEP 0 — CONCEPTUAL QUESTIONS'),
        contains(
          'questions about the user\'s OWN data\n  phrased with "qué es"',
        ),
      );
    });

    test('QaPositionsSnapshot and QaMetricStrip are never swapped', () {
      expect(
        rules(),
        contains(
          'QaPositionsSnapshot is ONLY for the user\'s own totals; QaMetricStrip is\n  ONLY for comparing 2-3 tickers — never swap them.',
        ),
      );
    });

    test(
      'a single ticker never gets QaMetricStrip; 2-3 never get QaPriceChart',
      () {
        final comparing = ruleSection(rules(), 'COMPARING 2-3 TICKERS');
        expect(
          comparing,
          contains('QaMetricStrip is never for a single ticker.'),
        );
        expect(
          comparing,
          contains(
            '2-3 tickers never mean\n  QaPriceChart, QaTickerSnapshot or QaTickerMove',
          ),
        );
      },
    );

    test(
      'held + window → QaTickerMove wins over QaPriceChart; everything else single-ticker → QaPriceChart',
      () {
        final ranking = ruleSection(
          rules(),
          'WIDGET SELECTION GUIDE — RANKING',
        );
        final heldMove = ranking.indexOf(
          '7. ONE ticker the user HOLDS + an explicit time window → QaTickerMove',
        );
        final chart = ranking.indexOf('8. Any other question about ONE ticker');
        final fallback = ranking.indexOf(
          '9. Only if step 8 applies but price_chart_available is false',
        );
        expect(heldMove, isNonNegative);
        expect(heldMove, lessThan(chart));
        expect(chart, lessThan(fallback));
      },
    );

    test('a named pair is a comparison, never a ranking', () {
      final ranking = ruleSection(rules(), 'WIDGET SELECTION GUIDE — RANKING');
      expect(
        ranking.indexOf('5. 2-3 tickers'),
        lessThan(ranking.indexOf('6. Best / worst')),
      );
    });

    test(
      'market-wide superlatives never pose the user\'s holdings as "the market"',
      () {
        expect(
          ruleSection(rules(), 'BEST / WORST'),
          contains(
            'never pick tickers from\n  their portfolio pretending they represent the market',
          ),
        );
      },
    );

    test(
      'portfolio-wide period (QaPeriodChange) vs all-time (QaPnLBreakdown) stays separated',
      () {
        final temporal = ruleSection(rules(), 'TEMPORAL QUESTIONS');
        expect(
          temporal,
          contains(
            'NEVER use total_pnl_abs or QaPnLBreakdown for "esta semana"',
          ),
        );
      },
    );

    test('only one data widget, with a single written exception', () {
      final layout = ruleSection(rules(), 'LAYOUT');
      expect(layout, contains('2. At most ONE data widget'));
      expect(
        layout,
        contains(
          'The ONLY exception to "at most ONE data widget": in WHY / CAUSATION with\nnews_enrichment "ok", QaNewsSummary may follow the primary widget.',
        ),
      );
    });
  });
}
