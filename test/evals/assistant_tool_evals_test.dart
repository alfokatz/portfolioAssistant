// Evals del asistente contra el modelo REAL (OpenAI). No corre en la suite
// normal: cuesta dinero y no es determinístico.
//
//   RUN_ASSISTANT_EVALS=1 EVAL_PROXY_JWT=<jwt> \
//     flutter test test/evals/assistant_tool_evals_test.dart
//
// Pasa por el proxy `ai-chat` igual que la app (la key de OpenAI está en el
// servidor, nunca acá): por defecto el local de `supabase functions serve`
// (EVAL_PROXY_URL para otro), con el JWT de un usuario de prueba
// (EVAL_PROXY_JWT) y la anon key (EVAL_ANON_KEY, opcional en local). Ver
// docs/runbooks/ai-proxy-cutover.md → "Evals contra el proxy local".
//
// Usa el prompt y las tools de producción y fuentes de datos fake
// (Yahoo/Finnhub con fixtures): mide
// lo que decide el modelo — qué tools pide, con qué argumentos, qué widget
// elige — no la calidad de los datos.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:portfolio_assistant/domain/entities/company_fundamentals.dart';
import 'package:portfolio_assistant/domain/entities/symbol_search_result.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:dartz/dartz.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/yahoo_company_profile_client.dart';
import 'package:portfolio_assistant/features/assistant/data/analysis/company_analysis_data.dart';
import 'package:portfolio_assistant/features/assistant/data/market/earnings_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/fundamentals_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_fetcher.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/yahoo_quote_remote_data_source.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_toolset.dart';
import 'package:portfolio_assistant/features/assistant/tools/portfolio_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/weekly_free_analysis_grant.dart';
import 'package:portfolio_assistant/features/assistant/utils/analysis_prose_check.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';
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
      if (Platform.environment['EVAL_DEBUG'] == '1' && body['id'] == null) {
        final raw = utf8.decode(bytes);
        // ignore: avoid_print
        print(
          '!!! response ${response.statusCode} without id: '
          '${raw.substring(0, raw.length > 600 ? 600 : raw.length)}',
        );
      }
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
    this.weeklyFree = false,
  });

  final String id;
  final List<String> turns;
  final SubscriptionTier tier;

  /// El usuario tiene disponible el análisis Gold de cortesía de la semana.
  final bool weeklyFree;

  /// Devuelve la lista de problemas (vacía = pasa) del ÚLTIMO turno.
  final List<String> Function(_TurnLog last, List<_TurnLog> all) check;
}

class _TurnLog {
  final calls = <ToolCallRecord>[];
  final components = <String>[];
  String text = '';

  /// Propiedades del QaCompanyAnalysis TAL COMO SE MUESTRA (post-proceso).
  Map<String, Object?>? analysis;
  TurnEvidence evidence = TurnEvidence.empty;
  int quotaWeight = 0;

  /// Cuántas veces el turno gastó la cortesía semanal en el "servidor".
  int courtesyConsumed = 0;

  CompanyAnalysisData? get analysisData =>
      analysis == null
          ? null
          : CompanyAnalysisData.from(evidence, '${analysis!['ticker']}');

  /// Problemas (números sin respaldo, consejo) en el texto mostrado.
  List<String> get proseProblems {
    final a = analysis;
    final d = analysisData;
    if (a == null || d == null) return const [];
    final backing = d.backingNumbers.toList();
    final texts = <String>[
      if (a['summary'] is String) a['summary'] as String,
      if (a['newsTake'] is String) a['newsTake'] as String,
      for (final p in (a['keyPoints'] as List? ?? const []))
        if (p is Map && p['text'] is String) p['text'] as String,
      for (final m in (a['metrics'] as List? ?? const []))
        if (m is Map && m['explanation'] is String) m['explanation'] as String,
    ];
    return [
      for (final t in texts)
        for (final s in AnalysisProseCheck.sentences(t))
          ...AnalysisProseCheck.problemsIn(s, backing),
    ];
  }

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

List<String> _analysisOf(_TurnLog t, String ticker, {bool allTools = true}) => [
  ..._expect(
    t.components.contains('QaCompanyAnalysis'),
    'sin QaCompanyAnalysis: ${t.components}',
  ),
  ..._expect(
    '${t.analysis?['ticker']}'.toUpperCase() == ticker,
    'análisis de ${t.analysis?['ticker']} en vez de $ticker',
  ),
  if (allTools)
    for (final tool in const [
      'get_quote',
      'get_fundamentals',
      'get_earnings',
      'get_news',
    ])
      ..._expect(
        t.tickersOf(tool).contains(ticker) ||
            t.evidence.calls.any(
              (c) => c.name == tool && '${c.args['tickers']}'.contains(ticker),
            ),
        'no usó $tool($ticker)',
      ),
  // (f) nada inventado ni consejo en lo que se muestra
  ..._expect(t.proseProblems.isEmpty, 'texto: ${t.proseProblems}'),
  // (g) un análisis cuesta 1 consulta
  ..._expect(t.quotaWeight == 1, 'cuota ${t.quotaWeight}, no 1'),
];

/// Búsqueda de símbolos fija para los casos de acciones: "Apple" → AAPL;
/// "Alphabet" es ambigua a propósito (GOOGL / GOOG, dos clases de acción).
class _Symbols extends FakeSymbolSearchRepository {
  static const _byName = <String, List<SymbolSearchResult>>{
    'apple': [
      SymbolSearchResult(symbol: 'AAPL', description: 'APPLE INC', type: 'Common Stock'),
    ],
    'microsoft': [
      SymbolSearchResult(symbol: 'MSFT', description: 'MICROSOFT CORP', type: 'Common Stock'),
    ],
    'nvidia': [
      SymbolSearchResult(symbol: 'NVDA', description: 'NVIDIA CORP', type: 'Common Stock'),
    ],
    'alphabet': [
      SymbolSearchResult(symbol: 'GOOGL', description: 'ALPHABET INC-CL A', type: 'Common Stock'),
      SymbolSearchResult(symbol: 'GOOG', description: 'ALPHABET INC-CL C', type: 'Common Stock'),
    ],
  };

  @override
  Future<Either<HttpError, List<SymbolSearchResult>>> search(String query) async {
    final q = query.toLowerCase();
    for (final entry in _byName.entries) {
      if (q.contains(entry.key)) return Right(entry.value);
    }
    return const Right([]);
  }
}

const _actionTools = {'propose_buy', 'propose_sell', 'propose_delete_position'};

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime get _today => DateTime.now();

/// Propuestas ok del turno, de una tool en particular o de cualquiera.
List<ToolCallRecord> _proposals(_TurnLog t, [String? tool]) => [
  for (final c in t.calls)
    if (_actionTools.contains(c.name) &&
        (tool == null || c.name == tool) &&
        c.status == 'ok')
      c,
];

int _cards(_TurnLog t) =>
    t.components.where((c) => c == 'QaActionProposal').length;

/// El texto nunca dice que la operación ya quedó guardada: la confirma el
/// usuario en la card.
List<String> _notClaimedSaved(_TurnLog t) {
  final text = t.text.toLowerCase();
  const claims = ['ya quedó', 'guardé', 'registré', 'agregué', 'ya está registrad'];
  final hit = claims.where(text.contains).toList();
  return _expect(hit.isEmpty, 'dice que ya guardó: $hit');
}

/// Pide datos o aclara: ni propuesta ok ni card.
List<String> _asksInstead(_TurnLog t) => [
  ..._expect(_proposals(t).isEmpty, 'propuso con datos faltantes/ambiguos'),
  ..._expect(_cards(t) == 0, 'mostró una card: ${t.components}'),
];

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
  // Bug reportado: tras la card de fundamentals de BAC, "¿me analizás estos
  // fundamentales?" respondía "enviame los datos que querés que analice".
  _Case(
    'G2-bac-analiza-estos',
    ['Pasame los fundamentals de BAC', '¿me analizás estos fundamentales?'],
    (t, _) => [
      ..._expect(
        !RegExp(
          r'env[ií]a(me)?|pas[aá]me los datos|qu[eé] datos|especific',
          caseSensitive: false,
        ).hasMatch(t.text),
        'pidió datos en vez de usar lo mostrado',
      ),
      ..._expect(t.text.contains('BAC'), 'perdió el ticker BAC'),
    ],
  ),
  _Case(
    'G2-bac-analiza-estos-long',
    [
      '¿Qué acciones de finanzas me recomendás?',
      'sí por favor',
      'Pasame los fundamentals de BAC',
      '¿me analizás estos fundamentales?',
    ],
    (t, _) => [
      ..._expect(
        !RegExp(
          r'env[ií]a(me)?|pas[aá]me los datos|qu[eé] datos|especific',
          caseSensitive: false,
        ).hasMatch(t.text),
        'pidió datos en vez de usar lo mostrado',
      ),
    ],
  ),
  // ── Análisis de una empresa ──────────────────────────────────────────
  _Case('A-chip-bac', [
    'Haceme un análisis de BAC',
  ], (t, _) => _analysisOf(t, 'BAC')),
  _Case('B-analizame-nike', [
    'analizame Nike',
  ], (t, _) => _analysisOf(t, 'NKE')),
  _Case('B-que-opinas-apple', [
    '¿qué opinás de Apple?',
  ], (t, _) => _analysisOf(t, 'AAPL')),
  _Case(
    'C-bac-estos-fundamentales',
    ['Pasame los fundamentals de BAC', '¿me analizás estos fundamentales?'],
    (t, _) => [
      ..._analysisOf(t, 'BAC'),
      ..._expect(
        !RegExp(
          r'env[ií]a(me)?|pas[aá]me los datos|qu[eé] datos|especific',
          caseSensitive: false,
        ).hasMatch(t.text),
        'pidió datos en vez de usar lo mostrado',
      ),
    ],
  ),
  _Case(
    'D-held-aapl',
    ['Haceme un análisis de AAPL'],
    (t, _) => [
      ..._analysisOf(t, 'AAPL'),
      ..._expect(t.analysisData?.position != null, 'sin "En tu cartera"'),
    ],
  ),
  _Case(
    'E-premium-no-news',
    ['Haceme un análisis de BAC'],
    tier: SubscriptionTier.premium,
    (t, _) => [
      ..._analysisOf(t, 'BAC', allTools: false),
      ..._expect(
        t.analysisData?.newsStatus == AnalysisSourceStatus.locked,
        'noticias no quedaron como bloqueadas: ${t.analysisData?.newsStatus}',
      ),
      ..._expect(
        t.analysisData?.quoteStatus == AnalysisSourceStatus.ok,
        'el resto no se mostró (precio)',
      ),
    ],
  ),
  // El bug de contexto afectaba a cualquier seguimiento: "¿y eso es bueno?"
  // tras una card tiene que resolverse contra lo recién mostrado.
  // ── Planes: análisis de cortesía semanal ─────────────────────────────
  _Case(
    'P-premium-analysis-free',
    ['Haceme un análisis de BAC'],
    tier: SubscriptionTier.premium,
    weeklyFree: true,
    (t, _) => [
      ..._analysisOf(t, 'BAC'),
      ..._expect(
        t.courtesyConsumed == 1,
        'cortesía gastada ${t.courtesyConsumed} veces',
      ),
      ..._expect(
        t.analysisData?.isCourtesy == true,
        'no se marcó como cortesía',
      ),
      ..._expect(
        t.analysisData?.fundamentalsStatus == AnalysisSourceStatus.ok,
        'con cortesía las fuentes de Gold tenían que venir completas',
      ),
    ],
  ),
  _Case(
    'P-premium-analysis-nofree',
    ['Haceme un análisis de BAC'],
    tier: SubscriptionTier.premium,
    (t, _) => [
      ..._analysisOf(t, 'BAC', allTools: false),
      ..._expect(
        t.analysisData?.lockedGoldFeatures.isNotEmpty == true,
        'sin cortesía, lo de Gold tenía que quedar bloqueado',
      ),
      ..._expect(t.courtesyConsumed == 0, 'gastó una cortesía que no tenía'),
    ],
  ),
  _Case(
    'F-free-own-analysis',
    ['Haceme un análisis de AAPL'],
    tier: SubscriptionTier.free,
    weeklyFree: true,
    (t, _) => [
      ..._analysisOf(t, 'AAPL'),
      ..._expect(t.analysisData?.isCourtesy == true, 'no usó la cortesía'),
    ],
  ),
  _Case(
    'F-free-foreign-analysis',
    ['Haceme un análisis de BAC'],
    tier: SubscriptionTier.free,
    weeklyFree: true,
    (t, _) => [
      ..._expect(
        '${t.aborted}' == '${PaywallReason.marketDataLocked}',
        'esperaba el paywall de Premium (mercado ajeno), fue ${t.aborted}',
      ),
      ..._expect(
        t.courtesyConsumed == 0,
        'gastó la cortesía en un ticker ajeno',
      ),
    ],
  ),
  _Case(
    'P-premium-news-teaser',
    ['¿Qué noticias hay de NVDA?'],
    tier: SubscriptionTier.premium,
    (t, _) => [
      ..._expect(
        t.aborted == null,
        'cortó el turno con un paywall: ${t.aborted}',
      ),
      ..._expect(
        t.components.contains('QaGoldTeaser'),
        'sin bloque Gold: ${t.components}',
      ),
      ..._expect(
        t.quotaWeight == 0,
        'cobró ${t.quotaWeight} consulta(s) por algo bloqueado',
      ),
    ],
  ),
  _Case(
    'P-premium-invest',
    ['Tengo \$1000 para invertir en tecnología'],
    tier: SubscriptionTier.premium,
    (t, _) => [
      ..._expect(
        t.aborted == null,
        'Premium ya incluye simulaciones: ${t.aborted}',
      ),
      ..._expect(t.called('get_invest_candidates'), 'no simuló'),
    ],
  ),
  _Case(
    'generic-es-bueno-fundamentals',
    ['Pasame los fundamentals de Tesla', '¿y eso es bueno?'],
    (t, _) => [
      ..._expect(
        !RegExp(
          r'env[ií]a(me)?|qu[eé] datos|a qu[eé] te refer|especific',
          caseSensitive: false,
        ).hasMatch(t.text),
        'no resolvió "eso" contra lo recién mostrado',
      ),
      ..._expect(
        t.text.contains('TSLA') || t.text.contains('Tesla'),
        'perdió TSLA',
      ),
    ],
  ),
  _Case(
    'compare-2',
    ['Comparame AAPL y MSFT'],
    (t, _) => [
      ..._expect(
        t.components.any(
          (c) =>
              c == 'QaCompareChart' ||
              c == 'QaComparisonRow' ||
              c == 'QaMetricStrip',
        ),
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
    'retirement-20y',
    ['Quiero retirarme en 20 años con 500 mil dólares'],
    (t, _) => [
      ..._expect(
        t.called(
          'get_goal_projection',
          (a) =>
              a['target_amount'] == 500000 &&
              a['is_retirement'] == true &&
              a['risk'] == null &&
              '${a['target_date']}'.startsWith('2046'),
        ),
        'argumentos del retiro (sin inventar el riesgo)',
      ),
    ],
  ),
  _Case(
    'retirement-income',
    ['Quiero jubilarme en 25 años cobrando 3000 dólares por mes'],
    (t, _) => [
      ..._expect(
        t.called(
          'get_goal_projection',
          (a) =>
              a['desired_monthly_income'] == 3000 &&
              a['target_amount'] == null,
        ),
        'el ingreso deseado define la meta',
      ),
    ],
  ),
  // ---------------------------------------------------- acciones (F6)
  _Case(
    'action-buy-complete',
    ['Compré 10 acciones de Apple el 25 de septiembre'],
    (t, _) {
      final p = _proposals(t, 'propose_buy');
      return [
        ..._expect(p.length == 1, 'esperaba 1 propose_buy ok: $t'),
        if (p.isNotEmpty) ...[
          ..._expect(p.first.args['ticker'] == 'AAPL', 'ticker ${p.first.args}'),
          ..._expect(p.first.args['shares'] == 10, 'shares ${p.first.args}'),
          ..._expect(
            p.first.args['date'] == '${_today.year}-09-25',
            'fecha ${p.first.args['date']}',
          ),
          ..._expect(!p.first.args.containsKey('price_usd'), 'inventó el precio'),
        ],
        ..._expect(_cards(t) == 1, 'esperaba 1 QaActionProposal: ${t.components}'),
        ..._notClaimedSaved(t),
      ];
    },
  ),
  _Case(
    'action-buy-missing',
    ['Compré Apple'],
    (t, _) {
      final text = t.text.toLowerCase();
      return [
        ..._asksInstead(t),
        // Pide cantidad y fecha, juntas (con o sin signo de pregunta).
        ..._expect(
          text.contains('fecha') &&
              (text.contains('cuántas') ||
                  text.contains('cantidad') ||
                  text.contains('monto')),
          'no pidió cantidad y fecha juntas',
        ),
      ];
    },
  ),
  _Case(
    'action-buy-usd-yesterday',
    ['Ayer metí 500 dólares en NVDA'],
    (t, _) {
      final p = _proposals(t, 'propose_buy');
      return [
        ..._notClaimedSaved(t),
        ..._expect(p.length == 1, 'esperaba 1 propose_buy ok: $t'),
        if (p.isNotEmpty) ...[
          ..._expect(p.first.args['amount_usd'] == 500, 'monto ${p.first.args}'),
          ..._expect(!p.first.args.containsKey('shares'), 'convirtió a acciones'),
          ..._expect(
            p.first.args['date'] ==
                _day(_today.subtract(const Duration(days: 1))),
            'fecha ${p.first.args['date']}',
          ),
        ],
        ..._expect(_cards(t) == 1, 'esperaba 1 QaActionProposal'),
      ];
    },
  ),
  _Case(
    'action-ambiguous-company',
    ['Compré 5 acciones de Alphabet el 25 de septiembre'],
    (t, _) => [
      ..._asksInstead(t),
      ..._expect(
        t.text.contains('GOOGL') && t.text.contains('GOOG'),
        'no nombró las dos clases',
      ),
    ],
  ),
  _Case(
    'action-sell-all',
    ['Vendí todas mis AAPL hoy'],
    (t, _) {
      final p = _proposals(t, 'propose_sell');
      return [
        ..._expect(p.length == 1, 'esperaba 1 propose_sell ok: $t'),
        if (p.isNotEmpty) ...[
          ..._expect(p.first.args['ticker'] == 'AAPL', 'ticker'),
          ..._expect(
            p.first.args['all'] == true || p.first.args['shares'] == 2,
            'no vendió todo: ${p.first.args}',
          ),
          ..._expect(p.first.args['date'] == _day(_today), 'fecha'),
        ],
        ..._expect(_cards(t) == 1, 'esperaba 1 QaActionProposal'),
        ..._notClaimedSaved(t),
      ];
    },
  ),
  _Case(
    'action-two-operations',
    ['Ayer compré 3 acciones de Microsoft y vendí todas mis NVDA'],
    (t, _) => [
      ..._expect(_proposals(t, 'propose_buy').length == 1, 'compra: $t'),
      ..._expect(_proposals(t, 'propose_sell').length == 1, 'venta: $t'),
      ..._expect(_cards(t) == 2, 'esperaba 2 cards: ${t.components}'),
      ..._notClaimedSaved(t),
    ],
  ),
  _Case(
    'action-sell-exceeds',
    ['Ayer vendí 10 acciones de NVDA'],
    // Puede verlo en PORTFOLIO_BRIEF (tiene 2) o por exceeds_holdings de la
    // tool: lo que importa es que no proponga y diga cuántas tiene.
    (t, _) => [
      ..._asksInstead(t),
      ..._expect(t.text.contains('2'), 'no dijo cuántas tiene'),
    ],
  ),
  _Case(
    'action-delete',
    ['Borrá NVDA de mi cartera, la cargué mal'],
    (t, _) => [
      ..._expect(
        _proposals(t, 'propose_delete_position').length == 1,
        'esperaba propose_delete_position: $t',
      ),
      ..._expect(!t.called('propose_sell'), 'lo trató como venta'),
      ..._expect(_cards(t) == 1, 'esperaba 1 QaActionProposal'),
      ..._notClaimedSaved(t),
    ],
  ),
  _Case(
    'action-not-advice',
    ['¿Debería comprar AAPL?'],
    (t, _) => [
      ..._expect(
        !t.calls.any((c) => _actionTools.contains(c.name)),
        'propuso una operación ante un pedido de consejo',
      ),
      ..._expect(_cards(t) == 0, 'mostró una card'),
    ],
  ),
  _Case(
    'action-not-hypothetical',
    ['Si compro 10 MSFT, ¿cuánto pesaría en mi cartera?'],
    (t, _) => [
      ..._expect(
        !t.calls.any((c) => _actionTools.contains(c.name)),
        'propuso una operación ante una hipótesis',
      ),
      ..._expect(_cards(t) == 0, 'mostró una card'),
    ],
  ),
  _Case(
    'action-free',
    ['Ayer compré 10 acciones de AAPL'],
    tier: SubscriptionTier.free,
    (t, _) => [
      ..._expect(t.aborted != null, 'esperaba paywall (short-circuit): $t'),
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
      final jwt = Platform.environment['EVAL_PROXY_JWT'] ?? '';
      if (jwt.isEmpty) fail('EVAL_PROXY_JWT es obligatorio (ver runbook)');
      final proxy = AiProxyConfig.fixed(
        Uri.parse(
          Platform.environment['EVAL_PROXY_URL'] ??
              'http://127.0.0.1:54321/functions/v1/ai-chat',
        ),
        jwt,
        anonKey: Platform.environment['EVAL_ANON_KEY'],
      );
      // EVAL_REAL_DATA=1: Yahoo/Finnhub/Google reales en vez de fixtures —
      // para reproducir bugs que dependen de la forma real de los datos.
      AssistantDataSources? realData;
      if (Platform.environment['EVAL_REAL_DATA'] == '1') {
        dotenv.testLoad(
          fileInput: File('assets/env/.env.development').readAsStringSync(),
        );
        realData = AssistantDataSources(
          quoteRepository: QuoteRepositoryImpl(
            remoteDataSource: YahooQuoteRemoteDataSource(),
          ),
          preferences: FakePreferences(),
          earnings: EarningsFetcher(),
          fundamentals: FundamentalsFetcher(),
          news: NewsFetcher(),
        );
      }
      final report = <Map<String, Object?>>[];
      var failures = 0;

      final only = Platform.environment['EVAL_ONLY'];
      for (final c in _cases.where(
        (c) => only == null || only.split(',').contains(c.id),
      )) {
        // EVAL_CASE_DELAY_S: pausa entre casos para no chocar con el límite
        // de tokens por minuto de la key (sin esto, las latencias medidas
        // incluyen las esperas por 429).
        final delay = int.tryParse(
          Platform.environment['EVAL_CASE_DELAY_S'] ?? '',
        );
        if (delay != null) await Future<void>.delayed(Duration(seconds: delay));
        final recorder = _UsageRecorder();
        final service = AssistantOpenAiService(
          proxy: proxy,
          model: env['OPENAI_MODEL'] ?? 'gpt-4.1-mini',
          httpClient: recorder,
        );
        final logs = <_TurnLog>[];
        var courtesyLeft = c.weeklyFree;
        for (var i = 0; i < c.turns.length; i++) {
          final log = _TurnLog();
          final ctx = AssistantToolContext(
            tier: c.tier,
            summary: heldSummary,
            data:
                realData ??
                fakeDataSources(
                  symbols: _Symbols(),
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
                      t: const YahooCompanyProfile(
                        sector: 'Utilities',
                        beta: 1.0,
                      ),
                  }),
                ),
          );
          final courtesy = WeeklyFreeAnalysisGrant(
            ctx: ctx,
            available: courtesyLeft,
            consume: (_) async {
              log.courtesyConsumed++;
              final ok = courtesyLeft;
              courtesyLeft = false;
              return ok;
            },
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
              beforeRound: courtesy.beforeRound,
            );
            log.calls.addAll(outcome.toolCalls);
            log.quotaWeight = AssistantTurnPolicy.quotaWeight(outcome);
            log.evidence = service.evidenceFor(surfaceId);
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
                  final component = surface!.components['$id'];
                  final type = component?.type;
                  if (type != null) log.components.add(type);
                  if (type == 'QaCompanyAnalysis') {
                    log.analysis = Map<String, Object?>.from(
                      component!.properties,
                    );
                  }
                }
              }
            }
          } on TurnAbortedException catch (e) {
            log.aborted = e.reason;
          } catch (e, st) {
            log.aborted = 'error: $e';
            if (Platform.environment['EVAL_DEBUG'] == '1') {
              // ignore: avoid_print
              print('!!! ${c.id} turn $i: $e\n$st');
            }
          }
          log.ms = stopwatch.elapsedMilliseconds;
          logs.add(log);
        }
        if (Platform.environment['EVAL_PRINT_TEXT'] == '1') {
          for (final l in logs) {
            // ignore: avoid_print
            print(
              '--- ${c.id} text: ${l.text.replaceAll(RegExp(r'\s+'), ' ')}',
            );
          }
        }
        final problems = [
          // Un turno que se rompió nunca cuenta como aprobado (los casos
          // negativos — "no propuso nada" — pasaban con el turno caído).
          for (final l in logs)
            if (l.aborted is String) '${l.aborted}',
          ...c.check(logs.last, logs),
        ];
        // Regla de LAYOUT: como máximo un widget de datos (QaNewsSummary puede
        // acompañar en un "por qué"). Se reporta aparte, no hace fallar.
        const nonData = {'Column', 'Text', 'QaAnswerText', 'QaTipBanner'};
        final data =
            logs.last.components.where((w) => !nonData.contains(w)).toList();
        final layoutOk =
            data.length <= 1 ||
            (data.length == 2 && data.contains('QaNewsSummary')) ||
            // Una card por operación ([W:ACTION]).
            data.every((w) => w == 'QaActionProposal');
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
