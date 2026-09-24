// Comparación offline de Jev/TypeSafe contra un dataset de 18 casos
// armados a mano a partir de los ejemplos concretos que documenta
// `explorePromptRules` (lib/features/assistant/modes/explore/
// explore_prompt_rules.dart) — en particular el bug histórico real de
// confundir QaTickerSnapshot / QaTickerMove / QaMetricStrip (ver
// explore_prompt_rules_test.dart), que es la señal que más importa acá.
//
// Este NO es un test de CI: no hay dataset etiquetado real preexistente en
// el repo (ver la investigación previa), así que este es uno construido a
// partir de las reglas, no tráfico real. Requiere TYPESAFE_API_KEY seteada
// (ver JevShadowConfig) y hace llamadas de red reales a la API de
// TypeSafe — por eso se auto-desactiva (pasa trivialmente, imprimiendo un
// aviso) si la key no está configurada, en vez de fallar. Correr a mano
// con:
//   flutter test test/manual/jev_offline_regression_test.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/jev_shadow/jev_explore_criteria.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/jev_shadow/jev_shadow_config.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/jev_shadow/typesafe_client.dart';

class _Case {
  _Case(this.message, this.snapshot, this.expected);
  final String message;
  final Map<String, dynamic> snapshot;
  final String expected;
}

// Los tres widgets que históricamente se confundían entre sí (ver el
// comentario de arriba) — un mismatch entre estos tres es la señal más
// importante de todo este dataset, más que el accuracy agregado.
const _confusablePair = {
  'QaTickerSnapshot',
  'QaTickerMove',
  'QaMetricStrip',
};

Map<String, dynamic> _period(double changePct, {bool sufficient = true}) => {
  'change_pct': changePct,
  'price_start': 100.0,
  'price_end': 100 * (1 + changePct / 100),
  'has_sufficient_history': sufficient,
  'label_es': 'período',
};

Map<String, dynamic> _ticker({double price = 120.5, bool fetchOk = true}) {
  if (!fetchOk) return {'fetch_ok': false};
  return {
    'fetch_ok': true,
    'current_price': price,
    'periods': {
      'day': _period(1.2),
      'week': _period(-2.1),
      'month': _period(5.8),
      'quarter': _period(8.0),
      'year': _period(20.0),
    },
  };
}

Map<String, dynamic> _snapshot({
  Map<String, dynamic>? exploreTickers,
  Map<String, dynamic>? earningsCalendar,
  String earningsStatus = 'ok',
  List<Map<String, dynamic>>? newsSources,
  String newsStatus = 'ok',
}) {
  return {
    'mode': 'explore',
    'data_source': 'yahoo_finance',
    'as_of': DateTime.now().toUtc().toIso8601String(),
    'explore_tickers': exploreTickers ?? {},
    'earnings_calendar': earningsCalendar ?? {},
    'earnings_calendar_status': earningsStatus,
    'news_sources': newsSources ?? [],
    'news_enrichment': newsStatus,
  };
}

final _newsSample = [
  {
    'title': 'Apple supera expectativas de ingresos en el trimestre',
    'snippet': 'Los ingresos por servicios impulsaron el resultado.',
    'url': 'https://example.com/a',
    'source': 'Reuters',
    'published_at': DateTime.now().toUtc().toIso8601String(),
  },
];

final _cases = [
  _Case(
    '¿cómo le fue a NVDA este mes?',
    _snapshot(exploreTickers: {'NVDA': _ticker()}),
    'QaTickerMove',
  ),
  _Case(
    'movimiento de AAPL en la última semana',
    _snapshot(exploreTickers: {'AAPL': _ticker()}),
    'QaTickerMove',
  ),
  _Case(
    '¿subió o bajó MSFT hoy?',
    _snapshot(exploreTickers: {'MSFT': _ticker()}),
    'QaTickerMove',
  ),
  _Case(
    '¿cómo vino TSLA en los últimos 3 meses?',
    _snapshot(exploreTickers: {'TSLA': _ticker()}),
    'QaTickerMove',
  ),
  _Case(
    '¿cómo le fue a NVDA este año?',
    _snapshot(exploreTickers: {'NVDA': _ticker()}),
    'QaTickerMove',
  ),
  _Case(
    '¿cómo está AAPL?',
    _snapshot(exploreTickers: {'AAPL': _ticker()}),
    'QaTickerSnapshot',
  ),
  _Case(
    'dame un pantallazo de NVDA',
    _snapshot(exploreTickers: {'NVDA': _ticker()}),
    'QaTickerSnapshot',
  ),
  _Case(
    '¿cómo vienen hoy NVDA, AAPL y MSFT?',
    _snapshot(
      exploreTickers: {
        'NVDA': _ticker(),
        'AAPL': _ticker(),
        'MSFT': _ticker(),
      },
    ),
    'QaMetricStrip',
  ),
  _Case(
    'comparame NVDA y AMD esta semana',
    _snapshot(exploreTickers: {'NVDA': _ticker(), 'AMD': _ticker()}),
    'QaMetricStrip',
  ),
  _Case(
    '¿cuándo reporta resultados NVDA?',
    _snapshot(
      exploreTickers: {'NVDA': _ticker()},
      earningsCalendar: {
        'NVDA': {
          'next_report': {
            'date_label': '13 nov 2026',
            'fiscal_period_label': 'T3 FY26',
          },
        },
      },
    ),
    'QaEarningsCalendar',
  ),
  _Case(
    '¿cómo le fue a MSFT en su último reporte?',
    _snapshot(
      exploreTickers: {'MSFT': _ticker()},
      earningsCalendar: {
        'MSFT': {
          'latest_result': {
            'report_date_label': '24 jul 2026',
            'eps_actual': 3.30,
            'eps_estimate': 3.10,
            'beat': true,
          },
        },
      },
    ),
    'QaEarningsCalendar',
  ),
  _Case(
    '¿qué noticias hay de AAPL?',
    _snapshot(
      exploreTickers: {'AAPL': _ticker()},
      newsSources: _newsSample,
      newsStatus: 'ok',
    ),
    'QaNewsSummary',
  ),
  _Case(
    'noticias recientes de NVDA',
    _snapshot(
      exploreTickers: {'NVDA': _ticker()},
      newsSources: _newsSample,
      newsStatus: 'ok',
    ),
    'QaNewsSummary',
  ),
  _Case(
    '¿qué es la diversificación?',
    _snapshot(),
    'QaAnswerText',
  ),
  _Case(
    '¿cuánto volumen operó AAPL hoy?',
    _snapshot(exploreTickers: {'AAPL': _ticker()}),
    'QaAnswerText',
  ),
  _Case(
    '¿cómo está XYZ?',
    _snapshot(exploreTickers: {'XYZ': _ticker(fetchOk: false)}),
    'QaAnswerText',
  ),
  _Case(
    '¿qué noticias hay de AAPL?',
    _snapshot(exploreTickers: {'AAPL': _ticker()}, newsStatus: 'locked'),
    'QaAnswerText',
  ),
  _Case(
    '¿cuándo reporta resultados NVDA?',
    _snapshot(
      exploreTickers: {'NVDA': _ticker()},
      earningsStatus: 'empty',
    ),
    'QaAnswerText',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Jev offline regression vs. explorePromptRules cases', () async {
    await dotenv.load(fileName: 'assets/env/.env.development');

    if (!JevShadowConfig.isEnabled) {
      // ignore: avoid_print
      print(
        '[JevShadow] TYPESAFE_API_KEY no configurada — comparación offline '
        'no corre. Seteala en assets/env/.env.development para ejecutarla.',
      );
      return;
    }

    final client = TypeSafeClient();
    var correct = 0;
    final mismatches = <String>[];
    final confusablePairMismatches = <String>[];

    // ignore: avoid_print
    print(
      '${'MENSAJE'.padRight(42)} ${'ESPERADO'.padRight(18)} '
      '${'JEV'.padRight(18)} ${'OK'.padRight(4)}${'CONF'.padRight(6)}MS',
    );

    for (final c in _cases) {
      final state = {...c.snapshot, 'user_message': c.message};
      final result = await client.chooseWidget(
        state: state,
        criteria: jevExploreWidgetCriteria,
        instructions: jevExploreWidgetQuestionInstructions,
      );

      result.fold(
        (error) {
          mismatches.add('${c.message} -> ERROR ${error.code}');
          // ignore: avoid_print
          print('${c.message.padRight(42)} ${c.expected.padRight(18)} ERROR:${error.code}');
          return;
        },
        (answer) {
          final isMatch = answer.choice == c.expected;
          if (isMatch) {
            correct++;
          } else {
            final note =
                '${c.message} -> esperado ${c.expected}, Jev eligió '
                '${answer.choice} (conf ${answer.confidence.toStringAsFixed(2)})';
            mismatches.add(note);
            if (_confusablePair.contains(c.expected) &&
                _confusablePair.contains(answer.choice)) {
              confusablePairMismatches.add(note);
            }
          }
          // ignore: avoid_print
          print(
            '${c.message.padRight(42)} ${c.expected.padRight(18)} '
            '${answer.choice.padRight(18)} ${(isMatch ? '✓' : '✗').padRight(4)}'
            '${answer.confidence.toStringAsFixed(2).padRight(6)}'
            '${answer.latency.inMilliseconds}',
          );
          return;
        },
      );
    }

    final accuracy = correct / _cases.length * 100;
    // ignore: avoid_print
    print(
      '\nAccuracy: $correct/${_cases.length} (${accuracy.toStringAsFixed(1)}%)',
    );

    if (mismatches.isNotEmpty) {
      // ignore: avoid_print
      print('\nCasos divergentes:');
      for (final m in mismatches) {
        // ignore: avoid_print
        print('  - $m');
      }
    }

    if (confusablePairMismatches.isNotEmpty) {
      // ignore: avoid_print
      print(
        '\n⚠ Confusión entre QaTickerSnapshot/QaTickerMove/QaMetricStrip '
        '(el bug histórico real, ver explore_prompt_rules_test.dart):',
      );
      for (final m in confusablePairMismatches) {
        // ignore: avoid_print
        print('  - $m');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
