import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_prompt_rules.dart';

import '../characterization/rules_contract.dart';

/// Migración 1:1 de los 23 tests de `explore_prompt_rules_test.dart` a las
/// reglas unificadas. Cada test lleva el id `EX-NN` y el nombre original.
///
/// Donde una aserción cambió, dice `CHANGED:` y por qué — siempre por una
/// de estas dos causas, nunca por relajar la regla:
/// - claves del snapshot renombradas (`explore_tickers.{T}` → `tickers.{T}`,
///   "MULTIPLE TICKERS AT ONCE" → "COMPARING 2-3 TICKERS"), o
/// - la decisión 4 (ticker EN CARTERA + período → QaTickerMove antes que
///   QaPriceChart).
void main() {
  const r = unifiedPromptRules;

  test('EX-01 has an explicit text-vs-widget decision rule', () {
    expect(r, contains('WHEN TO USE PLAIN TEXT VS. A WIDGET'));
    expect(r, contains('QaAnswerText only'));
  });

  test(
    'EX-02 no longer has the old ambiguous QaTickerMove/QaMetricStrip line',
    () {
      expect(r, isNot(contains('only when snapshot data supports it')));
    },
  );

  test(
    'EX-03 QaTickerMove keeps its explicit rule (single ticker + explicit period), scoped to the no-history fallback',
    () {
      expect(r, contains('TICKER + EXPLICIT PERIOD'));
      expect(r, contains('periods.{period}.change_pct'));
      expect(r, contains('→ periods.day'));
      expect(r, contains('→ periods.week'));
      expect(r, contains('→ periods.month'));
      expect(r, contains('→ periods.quarter'));
      expect(r, contains('→ periods.year'));
      expect(r, contains('always means QaTickerMove, never QaTickerSnapshot'));
      expect(r, contains('Use QaTickerMove:'));
    },
  );

  group('simple price question → QaPriceChart', () {
    test(
      'EX-04 "¿a cuánto está AAPL?" is listed under the QaPriceChart default',
      () {
        final rule = ruleSection(r, 'PRICE / EVOLUTION OF ONE TICKER');
        expect(rule, contains('QaPriceChart WINS BY DEFAULT'));
        expect(rule, contains('"¿a cuánto está AAPL?"'));
        expect(rule, contains('"precio de NVDA"'));
        expect(rule, contains('"¿cómo está\n  MSFT?"'));
        expect(rule, contains('Use QaPriceChart:'));
      },
    );

    test('EX-05 no time window named → initialRange defaults to 1M', () {
      expect(r, contains('"1M" if they didn\'t name any'));
    });

    test(
      'EX-06 an explicit window maps to its initialRange, still QaPriceChart',
      () {
        expect(r, contains('periods.day, initialRange "1D"'));
        expect(r, contains('periods.week, initialRange "1W"'));
        expect(r, contains('periods.month, initialRange "1M"'));
        expect(r, contains('periods.quarter, initialRange "3M"'));
        expect(r, contains('periods.year, initialRange "1Y"'));
        expect(r, contains('initialRange\n  "ALL"'));
        // CHANGED: "The widget is still QaPriceChart" → "Not held: the widget
        // is still QaPriceChart" (decisión 4: en cartera + período → Move).
        expect(r, contains('Not held: the widget is still QaPriceChart'));
      },
    );

    test('EX-07 the ranking puts QaPriceChart before Snapshot/Move', () {
      final ranking = ruleSection(r, 'WIDGET SELECTION GUIDE — RANKING');
      expect(ranking, contains('first match wins'));
      expect(ranking, contains('THE default for single-ticker questions'));
      // CHANGED (decisión 4): el único QaTickerMove antes de QaPriceChart es
      // el de ticker EN CARTERA + período (paso 7). El fallback
      // Snapshot/Move sigue siempre después de QaPriceChart.
      final chart = ranking.indexOf('→ QaPriceChart');
      final snapshot = ranking.indexOf('QaTickerSnapshot');
      final fallbackMove = ranking.indexOf('QaTickerMove (time window named)');
      expect(chart, isNonNegative);
      expect(chart, lessThan(snapshot));
      expect(chart, lessThan(fallbackMove));
      final beforeChart = ranking.substring(0, chart);
      expect(
        'QaTickerMove'.allMatches(beforeChart).length,
        1,
        reason: 'only the held + window step may precede QaPriceChart',
      );
      expect(
        beforeChart,
        contains(
          'ONE ticker the user HOLDS + an explicit time window → QaTickerMove',
        ),
      );
    });

    test('EX-08 the old "QaTickerSnapshot default" framing is gone', () {
      expect(r, isNot(contains('OVERRIDES the QaTickerSnapshot default')));
      expect(
        r,
        isNot(
          contains('Single ticker, no time window named: QaTickerSnapshot'),
        ),
      );
    });
  });

  group('"why did it rise/fall" → QaPriceChart + explanation in text', () {
    test(
      'EX-09 causation questions are listed under the QaPriceChart default',
      () {
        final rule = ruleSection(r, 'PRICE / EVOLUTION OF ONE TICKER');
        expect(rule, contains('"¿por qué subió NVDA?"'));
        expect(rule, contains('"¿por qué bajó\n  AAPL esta semana?"'));
        expect(
          rule,
          contains('the explanation itself still goes in QaAnswerText'),
        );
      },
    );

    test('EX-10 WHY / CAUSATION uses QaPriceChart as the primary widget', () {
      final why = ruleSection(r, 'WHY / CAUSATION');
      // CHANGED (decisión 4): el widget primario es el mismo que para
      // cualquier pregunta de un ticker — QaPriceChart salvo en cartera +
      // período (QaTickerMove) o sin histórico (fallback).
      expect(
        why,
        contains(
          'Primary widget: for a ticker, the same as any single-ticker question',
        ),
      );
      expect(
        why,
        contains(
          'else QaPriceChart, or its\nfallback if price_chart_available is false',
        ),
      );
      expect(why, contains('The explanation itself goes in QaAnswerText.'));
      expect(
        why,
        isNot(
          contains(
            'via QaTickerSnapshot or\n  QaTickerMove as the primary widget',
          ),
        ),
      );
    });
  });

  group('ticker without historical data → QaTickerSnapshot/QaTickerMove', () {
    test('EX-11 QaPriceChart requires price_chart_available', () {
      // CHANGED: explore_tickers.{TICKER} → tickers.{TICKER}.
      expect(r, contains('tickers.{TICKER}.price_chart_available is true'));
      expect(r, isNot(contains('explore_tickers')));
      expect(
        r,
        contains('price_chart_available is false, go to "FALLBACK ONLY"'),
      );
    });

    test(
      'EX-12 Snapshot/Move are documented as fallback, not equal alternatives',
      () {
        final fallback = ruleSection(r, 'FALLBACK ONLY');
        expect(fallback, contains('NOT alternatives of equal weight'));
        expect(fallback, contains('price_chart_available is false'));
        expect(fallback, contains('No time window named → QaTickerSnapshot'));
        expect(fallback, contains('Use QaTickerMove:'));
        expect(fallback, contains("don't apologize for the missing chart"));
      },
    );

    test(
      'EX-13 the ranking only reaches Snapshot/Move when there is no history',
      () {
        // CHANGED: el paso del ranking pasó de 4 a 8 (hay más pasos antes).
        expect(
          ruleSection(r, 'WIDGET SELECTION GUIDE — RANKING'),
          contains('Only if step 8 applies but price_chart_available is false'),
        );
      },
    );
  });

  test('EX-14 2-3 tickers still mean QaMetricStrip, never QaPriceChart', () {
    // CHANGED: redacción de la sección de comparaciones (C1–C6).
    expect(
      r,
      contains(
        '2-3 tickers never mean\n  QaPriceChart, QaTickerSnapshot or QaTickerMove',
      ),
    );
  });

  test(
    'EX-15 QaMetricStrip has an explicit rule: 2-3 tickers at once, never a single ticker',
    () {
      // CHANGED: "MULTIPLE TICKERS AT ONCE" → "COMPARING 2-3 TICKERS".
      expect(r, contains('COMPARING 2-3 TICKERS'));
      expect(r, contains('Use QaMetricStrip, one item per ticker'));
      expect(r, contains('never for a single ticker'));
    },
  );

  test(
    'EX-16 states plainly that volume/open/high/low/market cap are not available',
    () {
      expect(r, contains('NO volume, open, high, low'));
    },
  );

  test(
    'EX-17 EARNINGS CALENDAR: "when does X report" with examples and an honest fallback',
    () {
      expect(r, contains('EARNINGS CALENDAR'));
      expect(r, contains('WHEN a company next reports results'));
      expect(r, contains('next_report.date_label'));
      expect(
        r,
        contains('No tengo la fecha del próximo reporte de X ahora mismo'),
      );
      expect(r, contains('never guess a date'));
    },
  );

  test(
    'EX-18 EARNINGS CALENDAR: "how did the last report go" with examples and an honest fallback',
    () {
      expect(r, contains("HOW a company's LAST report went"));
      expect(r, contains('latest_result.eps_actual'));
      expect(r, contains('latest_result.eps_estimate'));
      expect(r, contains('not repeated in text'));
      expect(r, contains('never invent EPS numbers'));
    },
  );

  test(
    'EX-19 NEWS: headline questions use QaNewsSummary, with freshness and honest empty/failed',
    () {
      expect(r, contains('When the user asks specifically for news/headlines'));
      expect(r, contains('QaNewsSummary'));
      expect(r, contains('news_sources[].published_at'));
      expect(r, contains('more than 3 days old, the label MUST'));
      expect(r, contains('No tengo noticias recientes sobre X'));
      expect(r, contains("news couldn't be fetched right now"));
    },
  );

  test(
    'EX-20 NEWS section no longer promises OpenAI web search as the source',
    () {
      expect(r, isNot(contains('web search')));
      expect(r, contains('Finnhub'));
    },
  );

  test(
    'EX-21 EARNINGS CALENDAR treats "locked" as a distinct cause from empty/failed',
    () {
      expect(r, contains("'ok'|'empty'|'failed'|'locked'"));
      expect(r, contains('THREE DIFFERENT CAUSES'));
      expect(r, contains('earnings_calendar_status is "locked"'));
      expect(r, contains('no está disponible en tu plan'));
      expect(r, contains('no tengo información'));
      expect(r, contains('NOT a data gap'));
    },
  );

  test(
    'EX-22 NEWS treats "locked" as a distinct cause — never "no encontré noticias"',
    () {
      expect(r, contains("'skipped'|'ok'|'empty'|'failed'|'locked'"));
      expect(r, contains('news_enrichment is "locked"'));
      expect(r, contains('están disponibles en tu plan'));
      expect(r, contains('no encontré noticias'));
    },
  );

  test(
    'EX-23 the unified catalog systemPromptFragments include the decision rule',
    () {
      // CHANGED: `AssistantCatalog.buildFor(explore)` → catálogo unificado.
      final joined = UnifiedAssistantCatalog.build().systemPromptFragments.join(
        '\n',
      );
      expect(joined, contains('WHEN TO USE PLAIN TEXT VS. A WIDGET'));
    },
  );
}
