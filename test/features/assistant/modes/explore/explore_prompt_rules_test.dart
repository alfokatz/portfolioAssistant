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

    // Regresión: QaTickerMove y QaMetricStrip estaban registrados en el
    // catálogo de explore pero la única mención que tenían en el prompt
    // era "use QaTickerMove or QaMetricStrip only when snapshot data
    // supports it" — sin ningún caso de uso concreto, así que el modelo
    // nunca tenía una señal para preferirlos sobre QaTickerSnapshot. Estos
    // tests verifican que esa línea ambigua desapareció y que cada widget
    // tiene ahora una regla explícita, con el mismo nivel de detalle que
    // ya usa "TICKER-SPECIFIC QUESTIONS" en modo portfolio.
    test('no longer has the old ambiguous QaTickerMove/QaMetricStrip line', () {
      expect(
        explorePromptRules,
        isNot(contains('only when snapshot data supports it')),
      );
    });

    test(
      'QaTickerMove keeps its explicit rule (single ticker + explicit '
      'period), now scoped to the no-history fallback',
      () {
        expect(explorePromptRules, contains('TICKER + EXPLICIT PERIOD'));
        expect(explorePromptRules, contains('periods.{period}.change_pct'));
        // Los cinco mapeos de período — day/week/month igual que antes, más
        // quarter/year (ver ExploreContextBuilder, que ya los computa desde
        // el mismo historial que trae getHistoricalDaily, sin fetch extra).
        expect(explorePromptRules, contains('→ periods.day'));
        expect(explorePromptRules, contains('→ periods.week'));
        expect(explorePromptRules, contains('→ periods.month'));
        expect(explorePromptRules, contains('→ periods.quarter'));
        expect(explorePromptRules, contains('→ periods.year'));
        expect(
          explorePromptRules,
          contains('always means QaTickerMove, never QaTickerSnapshot'),
        );
        expect(explorePromptRules, contains('Use QaTickerMove:'));
      },
    );

    // --- QaPriceChart ------------------------------------------------------
    // Regresión de ambigüedad (mismo tipo que el bug de 694cba3, donde
    // QaTickerMove/QaMetricStrip competían "de igual a igual" con
    // QaTickerSnapshot sin una regla que dijera cuál gana): el prompt
    // tiene que dejar explícito que QaPriceChart es EL default para una
    // pregunta de precio/evolución de un ticker, y que Snapshot/Move son
    // fallback por falta de histórico — nunca alternativas equivalentes.

    /// Sección del prompt entre [from] y el siguiente encabezado [to].
    String section(String from, String to) {
      final start = explorePromptRules.indexOf(from);
      final end = explorePromptRules.indexOf(to, start + from.length);
      expect(start, isNonNegative, reason: 'missing section "$from"');
      expect(end, greaterThan(start), reason: 'missing section "$to"');
      return explorePromptRules.substring(start, end);
    }

    group('simple price question → QaPriceChart', () {
      test('"¿a cuánto está AAPL?" is listed under the QaPriceChart default', () {
        final rule = section(
          'PRICE / EVOLUTION OF ONE TICKER',
          'TICKER + EXPLICIT PERIOD',
        );
        expect(rule, contains('QaPriceChart WINS BY DEFAULT'));
        expect(rule, contains('"¿a cuánto está AAPL?"'));
        expect(rule, contains('"precio de NVDA"'));
        expect(rule, contains('"¿cómo está\n  MSFT?"'));
        expect(rule, contains('Use QaPriceChart:'));
      });

      test('no time window named → initialRange defaults to 1M', () {
        expect(
          explorePromptRules,
          contains('"1M" if they didn\'t name any'),
        );
      });

      test('an explicit window maps to its initialRange, still QaPriceChart', () {
        expect(explorePromptRules, contains('periods.day, initialRange "1D"'));
        expect(explorePromptRules, contains('periods.week, initialRange "1W"'));
        expect(explorePromptRules, contains('periods.month, initialRange "1M"'));
        expect(explorePromptRules, contains('periods.quarter, initialRange "3M"'));
        expect(explorePromptRules, contains('periods.year, initialRange "1Y"'));
        expect(explorePromptRules, contains('initialRange\n  "ALL"'));
        expect(
          explorePromptRules,
          contains('The widget is still QaPriceChart'),
        );
      });

      test('the ranking puts QaPriceChart before Snapshot/Move', () {
        final ranking = section(
          'WIDGET SELECTION GUIDE — RANKING',
          'BROAD MARKET QUESTIONS',
        );
        expect(ranking, contains('first match wins'));
        expect(ranking, contains('THE default for single-ticker questions'));
        final chart = ranking.indexOf('→ QaPriceChart');
        final snapshot = ranking.indexOf('QaTickerSnapshot');
        final move = ranking.indexOf('QaTickerMove');
        expect(chart, isNonNegative);
        expect(chart, lessThan(snapshot));
        expect(chart, lessThan(move));
      });

      test('the old "QaTickerSnapshot default" framing is gone', () {
        expect(
          explorePromptRules,
          isNot(contains('OVERRIDES the QaTickerSnapshot default')),
        );
        expect(
          explorePromptRules,
          isNot(contains('Single ticker, no time window named: QaTickerSnapshot')),
        );
      });
    });

    group('"why did it rise/fall" → QaPriceChart + explanation in text', () {
      test('causation questions are listed under the QaPriceChart default', () {
        final rule = section(
          'PRICE / EVOLUTION OF ONE TICKER',
          'TICKER + EXPLICIT PERIOD',
        );
        expect(rule, contains('"¿por qué subió NVDA?"'));
        expect(rule, contains('"¿por qué bajó\n  AAPL esta semana?"'));
        expect(
          rule,
          contains('the explanation itself still goes in QaAnswerText'),
        );
      });

      test('WHY / CAUSATION uses QaPriceChart as the primary widget', () {
        final why = explorePromptRules.substring(
          explorePromptRules.indexOf('WHY / CAUSATION'),
        );
        expect(
          why,
          contains('Still show the move with QaPriceChart as the primary widget'),
        );
        expect(why, contains('The explanation itself goes in QaAnswerText.'));
        expect(
          why,
          contains('the primary widget is still QaPriceChart (or its\nfallback)'),
        );
        expect(
          why,
          isNot(contains('via QaTickerSnapshot or\n  QaTickerMove as the primary widget')),
        );
      });
    });

    group('ticker without historical data → QaTickerSnapshot/QaTickerMove', () {
      test('QaPriceChart requires price_chart_available', () {
        expect(
          explorePromptRules,
          contains('explore_tickers.{TICKER}.price_chart_available is true'),
        );
        expect(
          explorePromptRules,
          contains('price_chart_available is false, go to "FALLBACK ONLY"'),
        );
      });

      test('Snapshot/Move are documented as fallback, not equal alternatives', () {
        final fallback = section('FALLBACK ONLY', 'MULTIPLE TICKERS AT ONCE');
        expect(fallback, contains('NOT alternatives of equal weight'));
        expect(fallback, contains('price_chart_available is false'));
        expect(fallback, contains('No time window named → QaTickerSnapshot'));
        expect(fallback, contains('Use QaTickerMove:'));
        expect(fallback, contains("don't apologize for the missing chart"));
      });

      test('the ranking only reaches Snapshot/Move when there is no history', () {
        final ranking = section(
          'WIDGET SELECTION GUIDE — RANKING',
          'BROAD MARKET QUESTIONS',
        );
        expect(
          ranking,
          contains('Only if step 4 applies but price_chart_available is false'),
        );
      });
    });

    test('2-3 tickers still mean QaMetricStrip, never QaPriceChart', () {
      expect(
        explorePromptRules,
        contains('never QaPriceChart, QaTickerSnapshot or\n  QaTickerMove'),
      );
    });

    test(
      'QaMetricStrip has an explicit rule: 2-3 tickers at once, never a '
      'single ticker',
      () {
        expect(explorePromptRules, contains('MULTIPLE TICKERS AT ONCE'));
        expect(
          explorePromptRules,
          contains('Use QaMetricStrip, one item per ticker'),
        );
        expect(explorePromptRules, contains('never for a single ticker'));
      },
    );

    // Regresión: "¿cómo vino MSFT en los últimos 3 meses?" caía a texto
    // genérico de "no hay datos suficientes" porque ExploreContextBuilder
    // solo computaba day/week/month, aunque el historial que ya trae
    // getHistoricalDaily cubre de sobra un trimestre/año (mismo patrón que
    // PortfolioContextBuilder). Y "¿cuál es el volumen de AAPL?" no tiene
    // ningún dato que lo respalde (PriceCandle solo tiene date+close) — el
    // prompt ahora lo dice explícitamente en vez de dejar que el modelo
    // improvise una disculpa genérica.
    test('states plainly that volume/open/high/low/market cap are not available', () {
      expect(explorePromptRules, contains('NO volume, open, high, low'));
    });

    // EARNINGS CALENDAR: mismo nivel de rigor que TICKER + EXPLICIT PERIOD
    // arriba — ejemplos concretos, mapeo de campos explícito y fallback
    // honesto cuando earnings_calendar_status no es "ok".
    test(
      'EARNINGS CALENDAR has an explicit rule for "when does X report" with '
      'concrete examples and an honest fallback',
      () {
        expect(explorePromptRules, contains('EARNINGS CALENDAR'));
        expect(
          explorePromptRules,
          contains('WHEN a company next reports results'),
        );
        expect(explorePromptRules, contains('next_report.date_label'));
        expect(
          explorePromptRules,
          contains('No tengo la fecha del próximo reporte de X ahora mismo'),
        );
        expect(explorePromptRules, contains('never guess a date'));
      },
    );

    test(
      'EARNINGS CALENDAR has an explicit rule for "how did the last report '
      'go" with concrete examples and an honest fallback',
      () {
        expect(
          explorePromptRules,
          contains("HOW a company's LAST report went"),
        );
        expect(explorePromptRules, contains('latest_result.eps_actual'));
        expect(explorePromptRules, contains('latest_result.eps_estimate'));
        expect(explorePromptRules, contains('not repeated in text'));
        expect(explorePromptRules, contains('never invent EPS numbers'));
      },
    );

    // NEWS: reemplaza el bloque anterior basado en OpenAI web search
    // (texto libre parseado por regex) por Finnhub (JSON estructurado) —
    // estos tests fijan que el prompt ya no promete datos de "web search"
    // y que la frescura de la noticia es explícita, no implícita.
    test(
      'NEWS has an explicit rule for headline questions using QaNewsSummary, '
      'with a freshness requirement and an honest empty/failed fallback',
      () {
        expect(
          explorePromptRules,
          contains('When the user asks specifically for news/headlines'),
        );
        expect(explorePromptRules, contains('QaNewsSummary'));
        expect(explorePromptRules, contains('news_sources[].published_at'));
        expect(
          explorePromptRules,
          contains('more than 3 days old, the label MUST'),
        );
        expect(
          explorePromptRules,
          contains('No tengo noticias recientes sobre X'),
        );
        expect(
          explorePromptRules,
          contains("news couldn't be fetched right now"),
        );
      },
    );

    test('NEWS section no longer promises OpenAI web search as the source', () {
      expect(explorePromptRules, isNot(contains('web search')));
      expect(explorePromptRules, contains('Finnhub'));
    });

    // Regresión: un usuario sin acceso por plan (news_enrichment/
    // earnings_calendar_status = "locked") veía el mismo mensaje que un
    // usuario para el que Finnhub genuinamente no tiene datos ("empty") —
    // ambos sonaban a "no tengo información", ocultando que en realidad
    // era una restricción de plan. Estos tests fijan que el prompt trata
    // "locked" como una causa distinta, con su propio texto explícito, y
    // prohíbe expresamente mezclarlo con el lenguaje de "sin datos".
    test(
      'EARNINGS CALENDAR treats "locked" as a distinct cause from empty/failed, '
      'with its own plan-restriction wording',
      () {
        expect(explorePromptRules, contains("'ok'|'empty'|'failed'|'locked'"));
        expect(explorePromptRules, contains('THREE DIFFERENT CAUSES'));
        expect(explorePromptRules, contains('earnings_calendar_status is "locked"'));
        expect(explorePromptRules, contains('no está disponible en tu plan'));
        // La regla prohíbe explícitamente sonar a "no hay datos" para este caso.
        expect(explorePromptRules, contains('no tengo información'));
        expect(explorePromptRules, contains('NOT a data gap'));
      },
    );

    test(
      'NEWS treats "locked" as a distinct cause from empty/failed, with its '
      'own plan-restriction wording — never "no encontré noticias"',
      () {
        expect(
          explorePromptRules,
          contains("'skipped'|'ok'|'empty'|'failed'|'locked'"),
        );
        expect(explorePromptRules, contains('news_enrichment is "locked"'));
        expect(explorePromptRules, contains('están disponibles en tu plan'));
        expect(explorePromptRules, contains('no encontré noticias'));
      },
    );
  });

  group('AssistantCatalog integration', () {
    test('explore mode systemPromptFragments include the decision rule', () {
      final catalog = AssistantCatalog.buildFor(AssistantMode.explore);
      final joined = catalog.systemPromptFragments.join('\n');

      expect(joined, contains('WHEN TO USE PLAIN TEXT VS. A WIDGET'));
    });
  });
}
