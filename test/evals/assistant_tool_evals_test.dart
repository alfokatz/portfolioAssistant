// Evals del asistente contra el modelo REAL (OpenAI). No corre en la suite
// normal: cuesta dinero y no es determinístico.
//
//   RUN_ASSISTANT_EVALS=1 flutter test test/evals/assistant_tool_evals_test.dart
//
// Usa la OPENAI_API_KEY de assets/env/.env.development, el prompt y las tools
// de producción, y fuentes de datos fake (Yahoo/Finnhub con fixtures): mide
// lo que decide el modelo — qué tools pide, con qué argumentos, qué widget
// elige — no la calidad de los datos.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:portfolio_assistant/domain/entities/company_fundamentals.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/yahoo_company_profile_client.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_toolset.dart';
import 'package:portfolio_assistant/features/assistant/tools/portfolio_tools.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

import '../features/assistant/fakes/assistant_fakes.dart';

/// Guarda `usage` de cada respuesta real (dart_openai descarta cached_tokens).
class _UsageRecorder extends http.BaseClient {
  final _inner = http.Client();
  final usages = <Map<String, dynamic>>[];
  final statuses = <int>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (Platform.environment['EVAL_DEBUG'] == '1' && request is http.Request) {
      final messages =
          (jsonDecode(request.body)['messages'] as List).cast<Map>();
      final last = messages.last;
      final c = jsonEncode(last['content']);
      // ignore: avoid_print
      print(
        '>>> ${last['role']}: ...${c.substring(c.length > 300 ? c.length - 300 : 0)}',
      );
    }
    final response = await _inner.send(request);
    final bytes = await response.stream.toBytes();
    statuses.add(response.statusCode);
    try {
      final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (body['usage'] is Map) {
        usages.add(body['usage'] as Map<String, dynamic>);
      }
    } catch (_) {}
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

class _Case {
  const _Case(
    this.id,
    this.turns,
    this.check, {
    this.tier = SubscriptionTier.gold,
  });

  final String id;
  final List<String> turns;
  final SubscriptionTier tier;

  /// Devuelve la lista de problemas (vacía = pasa) del ÚLTIMO turno.
  final List<String> Function(_TurnLog last, List<_TurnLog> all) check;
}

class _TurnLog {
  final calls = <ToolCallRecord>[];
  final components = <String>[];
  String text = '';
  Object? aborted;
  int ms = 0;

  bool called(String name, [bool Function(Map<String, Object?> args)? where]) =>
      calls.any((c) => c.name == name && (where == null || where(c.args)));

  List<String> tickersOf(String name) => [
    for (final c in calls)
      if (c.name == name)
        for (final t in (c.args['tickers'] as List? ?? const []))
          '$t'.toUpperCase(),
  ];

  @override
  String toString() =>
      'tools=${calls.map((c) => '${c.name}${jsonEncode(c.args)}→${c.status}').toList()} '
      'widgets=$components aborted=$aborted ${ms}ms';
}

List<String> _expect(bool ok, String problem) => ok ? const [] : [problem];

final _cases = <_Case>[
  _Case('chat-hola', [
    'Hola',
  ], (t, _) => _expect(t.calls.isEmpty, 'tools en un saludo')),
  _Case('chat-gracias', [
    'Gracias!',
  ], (t, _) => _expect(t.calls.isEmpty, 'tools en un gracias')),
  _Case('chat-heroe', [
    'Sos un héroe',
  ], (t, _) => _expect(t.calls.isEmpty, 'tools en charla')),
  _Case(
    'conceptual-etf-spy',
    ['¿Qué es un ETF, como SPY?'],
    (t, _) => [
      ..._expect(t.calls.isEmpty, 'pidió datos para una pregunta conceptual'),
      ..._expect(
        !t.components.any(
          (c) => c == 'QaPriceChart' || c == 'QaTickerSnapshot',
        ),
        'widget de datos en conceptual',
      ),
    ],
  ),
  _Case(
    'portfolio-now',
    ['¿Cómo está mi cartera?'],
    (t, _) => [
      ..._expect(
        t.calls.isEmpty,
        'no hacía falta ninguna tool (PORTFOLIO_BRIEF)',
      ),
      ..._expect(
        t.components.contains('QaPositionsSnapshot'),
        'esperaba QaPositionsSnapshot',
      ),
    ],
  ),
  _Case(
    'G5-tengo-invertido',
    ['¿Cuánto tengo invertido?'],
    (t, _) => [
      ..._expect(
        !t.called('get_invest_candidates'),
        'confundió "invertido" con una simulación (G5)',
      ),
      ..._expect(
        t.components.contains('QaPositionsSnapshot'),
        'esperaba QaPositionsSnapshot',
      ),
    ],
  ),
  _Case(
    'price-aapl',
    ['¿A cuánto está AAPL?'],
    (t, _) => [
      ..._expect(
        t.tickersOf('get_quote').contains('AAPL'),
        'no pidió get_quote(AAPL)',
      ),
      ..._expect(
        t.components.contains('QaPriceChart'),
        'esperaba QaPriceChart',
      ),
    ],
  ),
  _Case(
    'G1-cuanto-subio',
    ['¿A cuánto está AAPL?', '¿cuánto subió?'],
    (t, _) => [
      ..._expect(
        !t.called('search_symbol'),
        'buscó un símbolo en un seguimiento',
      ),
      ..._expect(
        t.calls.every(
          (c) =>
              c.name != 'get_quote' ||
              t.tickersOf('get_quote').contains('AAPL'),
        ),
        'perdió el ticker AAPL',
      ),
      ..._expect(
        t.components.any(
          (c) =>
              c == 'QaPriceChart' ||
              c == 'QaTickerMove' ||
              c == 'QaTickerSnapshot',
        ),
        'sin widget de precio',
      ),
    ],
  ),
  _Case(
    'company-name-apple',
    ['¿Qué métricas tiene Apple?'],
    (t, _) => [
      ..._expect(
        t.tickersOf('get_fundamentals').contains('AAPL'),
        'no pidió fundamentals de AAPL',
      ),
      ..._expect(
        t.components.contains('QaFundamentals'),
        'esperaba QaFundamentals',
      ),
    ],
  ),
  _Case(
    'G6-roe-nvidia',
    ['¿Cuál es el ROE de Nvidia?'],
    (t, _) => [
      ..._expect(
        !t.tickersOf('get_quote').contains('ROE'),
        'tomó ROE como ticker (G6)',
      ),
      ..._expect(
        t.tickersOf('get_fundamentals').contains('NVDA'),
        'no pidió fundamentals de NVDA',
      ),
    ],
  ),
  _Case(
    'market-cap-apple',
    ['Market cap de Apple'],
    (t, _) => [
      ..._expect(
        !t.tickersOf('get_quote').contains('SPY'),
        'lo tomó como pregunta de mercado',
      ),
      ..._expect(
        t.tickersOf('get_fundamentals').contains('AAPL'),
        'no pidió fundamentals de AAPL',
      ),
    ],
  ),
  _Case(
    'G2-explicame',
    ['Fundamentals de AAPL', 'explicame cada uno de ellos'],
    (t, _) => [
      ..._expect(
        t.calls.isEmpty,
        'volvió a pedir datos para explicar lo ya mostrado',
      ),
      ..._expect(t.text.contains('•'), 'sin líneas "• " (EXPLAIN_METRICS)'),
    ],
  ),
  _Case(
    'compare-2',
    ['Comparame AAPL y MSFT'],
    (t, _) => [
      ..._expect(
        t.components.any((c) => c == 'QaComparisonRow' || c == 'QaMetricStrip'),
        'esperaba comparación',
      ),
    ],
  ),
  _Case(
    'B4-best-week',
    ['¿Cuál de mis acciones subió más esta semana?'],
    (t, _) => [
      ..._expect(
        t.called('get_portfolio_details'),
        'no pidió position_periods',
      ),
      ..._expect(t.components.contains('QaTopMovers'), 'esperaba QaTopMovers'),
    ],
  ),
  _Case(
    'market-today',
    ['¿Cómo está el mercado hoy?'],
    (t, _) => [
      ..._expect(
        t.tickersOf('get_quote').contains('SPY'),
        'no usó SPY de referencia',
      ),
    ],
  ),
  _Case(
    'why-nvda',
    ['¿Por qué bajó NVDA esta semana?'],
    (t, _) => [
      ..._expect(
        t.called('get_news'),
        'no buscó noticias para explicar la causa',
      ),
    ],
  ),
  _Case(
    'invest-renewables',
    ['Tengo \$500 para invertir en energía renovable'],
    (t, _) {
      final tickers = t.tickersOf('get_invest_candidates');
      return [
        ..._expect(
          t.called('get_invest_candidates', (a) => a['budget_usd'] == 500),
          'no pasó budget_usd=500',
        ),
        ..._expect(tickers.length >= 2, 'menos de 2 candidatos: $tickers'),
        ..._expect(
          !tickers.every({'AAPL', 'NVDA'}.contains),
          'repitió las tenencias en vez de buscar renovables: $tickers',
        ),
        ..._expect(
          t.components.any(
            (c) => c == 'QaBudgetSplit' || c == 'QaInvestOption',
          ),
          'sin widget de inversión',
        ),
      ];
    },
  ),
  for (final (id, question) in const [
    ('invest-defensive', 'Quiero algo defensivo para invertir 1000 dólares'),
    ('invest-health', '¿Me recomendás acciones de salud para invertir?'),
    ('invest-general', '¿En qué me conviene invertir 2000 dólares?'),
  ])
    _Case(id, [question], (t, _) {
      final ran = t.calls.where(
        (c) => c.name == 'get_invest_candidates' && c.status == 'ok',
      );
      final tickers = {
        for (final c in ran)
          for (final x in (c.args['tickers'] as List? ?? const [])) '$x',
      };
      return [
        ..._expect(ran.isNotEmpty, 'la simulación no corrió: $t'),
        ..._expect(
          tickers.difference({'AAPL', 'NVDA'}).length >= 2,
          'no eligió candidatos propios: $tickers',
        ),
      ];
    }),
  _Case(
    'G8-news-after-invest',
    ['Tengo \$500 para invertir en energía renovable', '¿y las noticias?'],
    (t, all) {
      final candidates = all.first.tickersOf('get_invest_candidates').toSet();
      return _expect(
        t.tickersOf('get_news').any(candidates.contains),
        'las noticias no son de los candidatos $candidates',
      );
    },
  ),
  _Case(
    'goal-10y',
    ['En 10 años quiero tener 100 mil dólares'],
    (t, _) => [
      ..._expect(
        t.called(
          'get_goal_projection',
          (a) =>
              a['target_amount'] == 100000 &&
              '${a['target_date']}'.startsWith('2036'),
        ),
        'argumentos de la meta',
      ),
    ],
  ),
  _Case(
    'free-not-held',
    ['¿A cuánto está AMZN?'],
    tier: SubscriptionTier.free,
    (t, _) => [
      ..._expect(t.aborted != null, 'esperaba paywall (short-circuit)'),
    ],
  ),
];

void main() {
  final enabled = Platform.environment['RUN_ASSISTANT_EVALS'] == '1';

  test(
    'assistant tool-calling evals (real model)',
    () async {
      final env = {
        for (final line
            in File('assets/env/.env.development').readAsLinesSync())
          if (line.contains('=') && !line.startsWith('#'))
            line.substring(0, line.indexOf('=')).trim(): line
                .substring(line.indexOf('=') + 1)
                .trim()
                .replaceAll('"', ''),
      };
      final report = <Map<String, Object?>>[];
      var failures = 0;

      final only = Platform.environment['EVAL_ONLY'];
      for (final c in _cases.where(
        (c) => only == null || only.split(',').contains(c.id),
      )) {
        final recorder = _UsageRecorder();
        final service = AssistantOpenAiService(
          apiKey: env['OPENAI_API_KEY'],
          model: env['OPENAI_MODEL'] ?? 'gpt-4.1-mini',
          httpClient: recorder,
        );
        final logs = <_TurnLog>[];
        for (var i = 0; i < c.turns.length; i++) {
          final log = _TurnLog();
          final ctx = AssistantToolContext(
            tier: c.tier,
            summary: heldSummary,
            data: fakeDataSources(
              fundamentals: FakeCompanyFundamentalsRepository(
                data: const CompanyFundamentals(
                  ticker: 'X',
                  peTTM: 38.6,
                  marketCapitalization: 3500000,
                  roeTTM: 150.2,
                  netMarginTTM: 24.3,
                  dividendYieldIndicatedAnnual: 0.45,
                  beta: 1.2,
                ),
              ),
              profiles: FakeProfileClient({
                for (final t in const [
                  'NEE',
                  'ENPH',
                  'FSLR',
                  'BEP',
                  'ICLN',
                  'TAN',
                  'RUN',
                  'PLUG',
                  'SEDG',
                  'AY',
                  'CWEN',
                  'ORA',
                  'NEP',
                ])
                  t: const YahooCompanyProfile(sector: 'Utilities', beta: 1.0),
              }),
            ),
          );
          final surfaceId = 'eval_${c.id}_$i';
          final stopwatch = Stopwatch()..start();
          try {
            final outcome = await service.ask(
              question: c.turns[i],
              portfolioBrief: PortfolioBrief.build(ctx),
              surfaceId: surfaceId,
              tools: AssistantToolset.build(ctx),
              abortCheck: (round) => AssistantTurnPolicy.paywallFor(round, ctx),
            );
            log.calls.addAll(outcome.toolCalls);
            final raw = service.log.currentTurn?.finalText ?? '';
            log.text = raw;
            // Lo que ve el usuario: la surface ya despachada (post normalizer
            // y guard de layout), no el texto crudo del modelo.
            final surface = service.controller.registry.getSurface(surfaceId);
            final root = surface?.components['root'];
            if (root != null) {
              log.components.add(root.type);
              final children = root.properties['children'];
              if (children is List) {
                for (final id in children) {
                  final type = surface!.components['$id']?.type;
                  if (type != null) log.components.add(type);
                }
              }
            }
          } on TurnAbortedException catch (e) {
            log.aborted = e.reason;
          } catch (e) {
            log.aborted = 'error: $e';
          }
          log.ms = stopwatch.elapsedMilliseconds;
          logs.add(log);
        }
        final problems = c.check(logs.last, logs);
        // Regla de LAYOUT: como máximo un widget de datos (QaNewsSummary puede
        // acompañar en un "por qué"). Se reporta aparte, no hace fallar.
        const nonData = {'Column', 'Text', 'QaAnswerText', 'QaTipBanner'};
        final data =
            logs.last.components.where((w) => !nonData.contains(w)).toList();
        final layoutOk =
            data.length <= 1 ||
            (data.length == 2 && data.contains('QaNewsSummary'));
        if (problems.isNotEmpty) failures++;
        final usage = recorder.usages;
        report.add({
          'id': c.id,
          'pass': problems.isEmpty,
          'problems': problems,
          'layout_ok': layoutOk,
          'turns': [for (final l in logs) l.toString()],
          'requests': usage.length,
          'http_statuses': recorder.statuses,
          'prompt_tokens': usage.fold<int>(
            0,
            (s, u) => s + (u['prompt_tokens'] as int? ?? 0),
          ),
          'cached_tokens': usage.fold<int>(
            0,
            (s, u) =>
                s +
                ((u['prompt_tokens_details'] as Map?)?['cached_tokens']
                        as int? ??
                    0),
          ),
          'completion_tokens': usage.fold<int>(
            0,
            (s, u) => s + (u['completion_tokens'] as int? ?? 0),
          ),
        });
        // ignore: avoid_print
        print(
          '${problems.isEmpty ? 'PASS' : 'FAIL'} ${c.id} ${logs.last} ${problems.join('; ')}',
        );
        service.dispose();
      }

      final out = Platform.environment['ASSISTANT_EVALS_REPORT'];
      if (out != null) {
        File(
          out,
        ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
      }
      // ignore: avoid_print
      print('EVALS: ${_cases.length - failures}/${_cases.length} passed');
    },
    skip:
        enabled
            ? false
            : 'set RUN_ASSISTANT_EVALS=1 to run against the real model',
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
