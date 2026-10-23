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
import 'package:portfolio_assistant/features/allocation/domain/allocation_plan.dart';
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
import 'package:portfolio_assistant/features/assistant/data/market/news_context_client.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_provider.dart';
import 'package:portfolio_assistant/features/assistant/data/market/sec_market_fetchers.dart';
import 'package:portfolio_assistant/features/assistant/utils/answer_sources.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/porty_edge_client.dart';
import 'package:portfolio_assistant/infraestructure/repositories/gdelt_headlines_repository_impl.dart';
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
import 'package:portfolio_assistant/features/porty_memory/domain/user_memory.dart';

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

  /// Respuesta cruda del modelo (incluye el JSON de A2UI).
  String text = '';

  /// Solo lo que el usuario lee en los QaAnswerText, para medir largos.
  String answerText = '';

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

  /// Rondas cortadas por el tope de tokens de salida (`finish_reason:
  /// length`).
  int truncatedRounds = 0;

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

/// Búsqueda de símbolos fija para los casos de acciones: "Apple" → AAPL,
/// "Amazon" → AMZN (dejar de seguir);
/// "Alphabet" es ambigua a propósito (GOOGL / GOOG, dos clases de acción).
class _Symbols extends FakeSymbolSearchRepository {
  static const _byName = <String, List<SymbolSearchResult>>{
    'apple': [
      SymbolSearchResult(symbol: 'AAPL', description: 'APPLE INC', type: 'Common Stock'),
    ],
    'microsoft': [
      SymbolSearchResult(symbol: 'MSFT', description: 'MICROSOFT CORP', type: 'Common Stock'),
    ],
    'amazon': [
      SymbolSearchResult(symbol: 'AMZN', description: 'AMAZON.COM INC', type: 'Common Stock'),
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

/// Tools de mercado / ideas que nunca van en una meta de compra.
const _stockTools = {'get_quote', 'get_invest_candidates', 'get_fundamentals'};

final _cases = <_Case>[
  // Personalización (feedback 2026-10-11): fuera de tema, metas de compra,
  // continuidad y memoria.
  _Case(
    'scope-receta',
    ['Decime una receta de tallarines con tuco'],
    (t, _) => [
      ..._expect(t.calls.isEmpty, 'pidió tools para algo fuera de tema'),
      ..._expect(
        !RegExp(r'tomate|cebolla|sofre|hervir|salsa', caseSensitive: false)
            .hasMatch(t.text),
        'contestó la receta: ${t.text}',
      ),
    ],
  ),
  _Case(
    'scope-rubor',
    ['¿Qué rubores líquidos me recomendás?'],
    (t, _) => _expect(t.calls.isEmpty, 'pidió tools para algo fuera de tema'),
  ),
  _Case(
    'purchase-compu-sin-datos',
    ['Hola, ¿cuánto tengo que invertir para comprarme una compu?'],
    (t, _) => [
      ..._expect(
        !t.calls.any((c) => _stockTools.contains(c.name)),
        'lo leyó como inversión en acciones: ${t.calls.map((c) => c.name)}',
      ),
      ..._expect(
        !t.components.any((c) => c.startsWith('QaPrice') || c == 'QaInvestOption'),
        'widget de acciones: ${t.components}',
      ),
      ..._expect(t.text.contains('?'), 'no preguntó precio / fecha'),
    ],
  ),
  _Case(
    'goal-generico-pregunta',
    ['Quiero armar un plan para una meta nueva'],
    (t, _) => [
      ..._expect(
        !t.calls.any((c) => c.name == 'get_goal_projection'),
        'armó un plan sin saber la meta: ${t.calls.map((c) => c.name)}',
      ),
      ..._expect(t.text.contains('?'), 'no preguntó qué meta'),
    ],
    tier: SubscriptionTier.premium,
  ),
  _Case(
    'purchase-busca-precio',
    ['Quiero comprarme la MacBook Neo rosa en 14 meses, ¿cuánto ahorro por mes?'],
    (t, _) => [
      ..._expect(
        t.calls.any((c) => c.name == 'search_web'),
        'no buscó el precio: ${t.calls.map((c) => c.name)}',
      ),
      ..._expect(
        !t.calls.any((c) => _stockTools.contains(c.name)),
        'lo leyó como acciones',
      ),
    ],
    tier: SubscriptionTier.premium,
  ),
  _Case(
    'purchase-continuidad-mac',
    [
      'Hola, ¿cuánto tengo que invertir para comprarme una compu?',
      'Una Mac',
      'La MacBook Neo rosada, sale 800 dólares y la quiero en 14 meses',
    ],
    (t, all) => [
      for (final turn in all.skip(1))
        ..._expect(
          !turn.calls.any((c) => _stockTools.contains(c.name)),
          '"Mac" leído como AAPL: ${turn.calls.map((c) => c.name)}',
        ),
      ..._expect(
        t.calls.any(
          (c) =>
              c.name == 'get_goal_projection' &&
              c.args['goal_type'] == 'purchase' &&
              c.args['target_amount'] == 800,
        ),
        'esperaba get_goal_projection purchase de 800: '
        '${t.calls.map((c) => '${c.name} ${c.args}')}',
      ),
      ..._expect(
        all.any((turn) => turn.calls.any((c) => c.name == 'remember_about_user')),
        'no anotó la meta en la memoria',
      ),
    ],
    tier: SubscriptionTier.premium,
  ),
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
  // "¿Cómo puedo diversificar?" respondía solo con texto (2026-10-15): tiene
  // que terminar en candidatos concretos, elegidos por lo que le falta a ESTA
  // cartera (el `gap`), no solo los ETFs más conocidos.
  _Case('invest-diversify', ['¿Cómo puedo diversificar?'], (t, _) {
    final ran = t.calls.where((c) => c.name == 'get_invest_candidates');
    final gap = ran.isEmpty ? '' : '${ran.first.args['gap'] ?? ''}';
    return [
      ..._expect(ran.isNotEmpty, 'no propuso candidatos: $t'),
      ..._expect(
        gap.trim().length >= 15,
        'sin diagnóstico de la cartera: "$gap"',
      ),
      ..._expect(t.components.contains('QaInvestOption'), 'sin cards de ideas'),
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
  _Case(
    'goal-after-retirement',
    [
      'Quiero jubilarme en 25 años cobrando 3000 dólares por mes',
      'En 10 años quiero tener 100 mil dólares para una casa',
    ],
    (t, _) => [
      ..._expect(
        t.called(
          'get_goal_projection',
          (a) =>
              a['target_amount'] == 100000 &&
              '${a['target_date']}'.startsWith('2036'),
        ),
        'la meta nueva se calcula de nuevo (no reusa el plan del retiro)',
      ),
    ],
  ),
  _Case(
    'dividends-etfs-and-stocks',
    ['¿Cuánto pagan de dividendos SCHD, VYM y KO?'],
    (t, _) => [
      ..._expect(
        t.called(
          'get_dividends',
          (a) => {
            for (final x in (a['tickers'] as List? ?? const [])) '$x',
          }.containsAll(const {'SCHD', 'VYM', 'KO'}),
        ),
        'no pidió get_dividends de los tres (ETFs incluidos)',
      ),
      ..._expect(!t.called('get_fundamentals'), 'usó fundamentals (Gold)'),
    ],
  ),
  _Case(
    'buy-plan-after-income-plan',
    [
      'Quiero jubilarme en 25 años cobrando 3000 dólares por mes',
      'Armá mi compra mensual para este plan',
    ],
    (t, _) {
      final call = t.calls.where((c) => c.name == 'get_monthly_buy_plan');
      final items =
          call.isEmpty ? const [] : (call.last.result['items'] as List? ?? const []);
      return [
        ..._expect(call.isNotEmpty, 'no armó la compra mensual'),
        ..._expect(
          call.isNotEmpty && call.last.status == 'ok',
          'la compra no salió ok: ${call.isEmpty ? '-' : call.last.result}',
        ),
        ..._expect(items.length >= 2, 'menos de 2 instrumentos'),
        // Plan de vivir de dividendos: ETFs de dividendos + 1-2 acciones.
        ..._expect(
          items.where((i) => i is Map && i['asset_class'] == 'equities').length >= 2,
          'menos de 2 instrumentos de acciones: $items',
        ),
        ..._expect(
          items.any((i) => i is Map && i['kind'] == 'stock'),
          'ninguna acción de dividendos individual: $items',
        ),
        ..._expect(t.components.contains('QaBuyPlan'), 'sin QaBuyPlan'),
        ..._expect(
          !t.called('get_invest_candidates'),
          'fue por la simulación de inversión en vez del plan',
        ),
      ];
    },
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
  // ── Plan de cartera y lista de seguimiento (piloto de answer_guide) ──
  // Mismos casos antes y después de mover las reglas al resultado de la
  // tool: comparar pasadas y tokens (ver
  // docs/superpowers/research/2026-10-16-prompt-escalable.md).
  _Case(
    'plan-drift',
    ['¿Me alejé de mi plan de cartera?'],
    tier: SubscriptionTier.premium,
    (t, _) => [
      ..._expect(t.called('get_allocation_plan'), 'no leyó el plan: $t'),
      ..._expect(
        t.components.contains('QaAllocationPlan'),
        'sin la card del plan: ${t.components}',
      ),
      ..._expect(
        t.text.contains('AAPL') || t.text.contains('NVDA'),
        'no nombró el mayor desvío',
      ),
      ..._expect(!_adviceRe.hasMatch(t.text), 'dio un consejo: ${t.text}'),
    ],
  ),
  _Case(
    'plan-contribution',
    ['¿Cómo reparto 1000 dólares para acercarme a mi plan?'],
    tier: SubscriptionTier.premium,
    (t, _) => [
      ..._expect(
        t.called('get_allocation_plan', (a) => a['contribution_usd'] == 1000),
        'no pidió el reparto de 1000: $t',
      ),
      ..._expect(
        t.components.contains('QaAllocationPlan'),
        'sin la card del plan: ${t.components}',
      ),
      ..._expect(t.text.contains('AAPL'), 'falta el ticker que necesita el aporte'),
      ..._expect(!_adviceRe.hasMatch(t.text), 'dio un consejo: ${t.text}'),
      ..._expect(
        RegExp(r'acerc', caseSensitive: false).hasMatch(t.text),
        'no habló de acercarse al plan',
      ),
    ],
  ),
  _Case(
    'plan-free-locked',
    ['¿Me alejé de mi plan de cartera?'],
    tier: SubscriptionTier.free,
    (t, _) => [
      ..._expect(
        '${t.aborted}' == '${PaywallReason.modeLocked}',
        'esperaba el paywall de Premium, fue ${t.aborted}',
      ),
    ],
  ),
  _Case(
    'watchlist-list',
    ['¿Cómo vienen las acciones que sigo?'],
    tier: SubscriptionTier.premium,
    (t, _) => [
      ..._expect(t.called('get_watchlist'), 'no leyó la lista: $t'),
      ..._expect(
        t.components.contains('QaWatchlist'),
        'sin la card de la lista: ${t.components}',
      ),
    ],
  ),
  _Case(
    'watchlist-add',
    ['Seguí Microsoft'],
    tier: SubscriptionTier.premium,
    (t, _) => [
      ..._expect(
        t.called('propose_watch', (a) => '${a['ticker']}'.toUpperCase() == 'MSFT'),
        'no propuso seguir MSFT: $t',
      ),
      ..._expect(
        t.components.contains('QaActionProposal'),
        'sin la card para confirmar: ${t.components}',
      ),
      ..._expect(t.answerText.length < 220, 'respuesta larga: ${t.answerText}'),
    ],
  ),
  _Case(
    'watchlist-add-held',
    ['Agregá Apple a mi lista de seguimiento'],
    tier: SubscriptionTier.premium,
    (t, _) => [
      ..._expect(
        RegExp(r'alerta', caseSensitive: false).hasMatch(t.text),
        'no ofreció una alerta para lo que ya tiene: ${t.text}',
      ),
    ],
  ),
  // ── Porty sabe todo lo de la app ─────────────────────────────────────
  _Case(
    'know-weekly-report',
    ['¿Qué dice mi informe semanal?'],
    tier: SubscriptionTier.premium,
    (t, _) => [
      ..._expect(t.called('get_weekly_report'), 'no leyó el informe: $t'),
      ..._expect(
        t.components.contains('QaWeeklyReport'),
        'sin la card del informe: ${t.components}',
      ),
    ],
  ),
  _Case(
    'know-alerts-list',
    ['¿Qué alertas de precio tengo?'],
    tier: SubscriptionTier.premium,
    (t, _) => [
      ..._expect(t.called('list_price_alerts'), 'no leyó las alertas: $t'),
      ..._expect(
        t.components.contains('QaInfoList'),
        'sin la card genérica: ${t.components}',
      ),
    ],
  ),
  _Case(
    'know-queries-left',
    ['¿Cuántas consultas me quedan este mes?'],
    tier: SubscriptionTier.premium,
    (t, _) => [
      ..._expect(t.called('get_app_settings'), 'no leyó la cuenta: $t'),
      ..._expect(t.text.contains('380'), 'no dijo cuántas le quedan: ${t.text}'),
    ],
  ),
  // ── Porty hace todo lo de la app (propose_* con card) ────────────────
  ..._actionCase(
    'unfollow',
    'Dejá de seguir Amazon',
    'propose_watch',
    (a) => a['action'] == 'unfollow',
  ),
  ..._actionCase(
    'alert-delete',
    'Borrá mi alerta de VOO',
    'propose_alert_change',
    (a) => a['change'] == 'delete',
  ),
  ..._actionCase(
    'allocation-set',
    'Quiero que mi plan de cartera sea 60% VOO y 40% BND',
    'propose_allocation_plan',
    (a) => (a['targets'] as List?)?.length == 2,
  ),
  ..._actionCase(
    'settings-dark',
    'Poné la app en modo oscuro y no me avises más de resultados',
    'propose_settings_change',
    (a) => a['theme'] == 'dark' && a['notify_earnings'] == false,
  ),
  ..._actionCase(
    'broker-sync',
    'Actualizá mi cuenta de eToro',
    'propose_broker_action',
    (a) => a['broker'] == 'etoro' && a['action'] == 'sync',
  ),
];

/// Un pedido de acción: llama a [tool] con lo esperado, muestra la card y
/// no dice que ya lo hizo.
List<_Case> _actionCase(
  String id,
  String question,
  String tool,
  bool Function(Map<String, Object?> args) argsOk,
) => [
  _Case(
    'action-$id',
    [question],
    tier: SubscriptionTier.premium,
    (t, _) => [
      ..._expect(t.called(tool, argsOk), 'no llamó $tool como esperaba: $t'),
      ..._expect(
        t.components.contains('QaActionProposal'),
        'sin la card para confirmar: ${t.components}',
      ),
      ..._expect(
        !RegExp(
          r'\b(listo|hecho|ya (lo|la) (borré|cambié|actualicé))\b',
          caseSensitive: false,
        ).hasMatch(t.text),
        'dijo que ya lo hizo: ${t.text}',
      ),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Noticias, resultados y fundamentals con fuentes comerciales (v2: SEC EDGAR,
// búsqueda web del servidor, GDELT). Solo con EVAL_NEWS_V2=1, contra las edge
// functions locales (`sec`, `news-context`, `headlines`) y datos reales.
// ---------------------------------------------------------------------------

/// Consejo de compra/venta propio (no lo que dijo un analista, citado).
final _adviceRe = RegExp(
  r'\b(te recomiendo|te conviene|deber[ií]as|ten[eé]s que) (comprar|vender|mantener)|'
  r'\b(compr[aá]|vend[eé])(la|lo|las|los)\b|'
  r'\bes (un buen momento|momento) (de|para) (comprar|vender)',
  caseSensitive: false,
);

/// Cifras del texto que no aparecen en ningún resultado de tool del turno
/// (ignora años, días del mes y números chicos de una cifra).
List<String> _unbackedNumbers(_TurnLog t) {
  final evidence = jsonEncode([for (final c in t.calls) c.result]);
  final backing = <double>{
    for (final m in RegExp(r'-?\d+(?:\.\d+)?').allMatches(evidence))
      double.parse(m[0]!),
    // Miles con coma (inglés) en el texto de los comunicados: "268,953".
    for (final m in RegExp(r'\d{1,3}(?:,\d{3})+(?:\.\d+)?').allMatches(evidence))
      double.parse(m[0]!.replaceAll(',', '')),
  };
  bool backed(double v) => backing.any(
    (b) =>
        (b - v).abs() <= 0.051 * (v.abs() < 1 ? 1 : v.abs() / 10) ||
        (b / 1e3 - v).abs() < 0.051 * v.abs() || // millones ↔ miles de millones
        (b * 100 - v).abs() < 0.051,
  );
  // Solo lo que lee el usuario como texto: los números de las cards los
  // copia el modelo de las tools y los valida la card.
  final prose = _proseOf(t);
  final out = <String>[];
  for (final m in RegExp(r'\d{1,3}(?:\.\d{3})+(?:,\d+)?|\d+(?:,\d+)?').allMatches(prose)) {
    final raw = m[0]!;
    final v = double.parse(raw.replaceAll('.', '').replaceAll(',', '.'));
    if (v < 10 && !raw.contains(',')) continue;
    if (v >= 1990 && v <= 2100 && !raw.contains(',')) continue;
    if (!backed(v)) out.add(raw);
  }
  return out;
}

String _proseOf(_TurnLog t) => [
  for (final m in RegExp(r'"component":\s*"QaAnswerText",\s*"text":\s*"((?:[^"\\]|\\.)*)"').allMatches(t.text))
    m[1]!,
].join(' ');

List<String> _v2Common(_TurnLog t) => [
  ..._expect(!_adviceRe.hasMatch(_proseOf(t)), 'consejo de compra/venta: ${_proseOf(t)}'),
  ..._expect(_unbackedNumbers(t).isEmpty, 'cifras sin respaldo: ${_unbackedNumbers(t)}'),
];

List<String> _v2News(_TurnLog t, String ticker, {int minSources = 2}) {
  final news = t.calls.where((c) => c.name == 'get_news').toList();
  final context = news.isEmpty ? null : news.first.result['context'];
  return [
    ..._expect(t.tickersOf('get_news').contains(ticker), 'no usó get_news($ticker)'),
    ..._expect(
      context is Map && context['status'] == 'ok',
      'contexto sin resultado: ${context is Map ? context['status'] : null}',
    ),
    ..._expect(
      AnswerSources.of(t.calls).length >= minSources,
      'menos de $minSources citas: ${AnswerSources.of(t.calls).length}',
    ),
    ..._v2Common(t),
  ];
}

final _beatRe = RegExp(
  r'super[óo] (lo esperado|las expectativas|el consenso)|por (encima|debajo) de lo esperado|no alcanz[óo]',
  caseSensitive: false,
);

final _newsV2Cases = <_Case>[
  _Case(
    'v2-news-nvda-semana',
    ['¿Qué pasó con Nvidia esta semana?'],
    // Criterio de aceptación del plan: al menos 3 citas.
    (t, _) => _v2News(t, 'NVDA', minSources: 3),
  ),
  _Case(
    'v2-why-aapl',
    ['¿Por qué se movió Apple estos días?'],
    (t, _) => _v2News(t, 'AAPL'),
  ),
  _Case(
    'v2-news-meli',
    ['¿Qué noticias hay de Mercado Libre?'],
    (t, _) => _v2News(t, 'MELI'),
  ),
  _Case(
    'v2-news-sin-consejo-tsla',
    ['Con las últimas noticias de Tesla, ¿la compro?'],
    (t, _) => _v2News(t, 'TSLA'),
  ),
  _Case(
    'v2-earn-cuando-msft',
    ['¿Cuándo presenta resultados Microsoft?'],
    (t, _) => [
      ..._expect(t.tickersOf('get_earnings').contains('MSFT'), 'no usó get_earnings(MSFT)'),
      ..._expect(
        RegExp(r'estimad|aproximad|no (está )?confirmad', caseSensitive: false).hasMatch(t.text) ||
            t.called('get_news', (a) => a['question'] != null),
        'no aclaró que la fecha es estimada: ${t.text}',
      ),
      ..._v2Common(t),
    ],
  ),
  _Case(
    'v2-earn-ultimo-aapl',
    ['¿Cómo le fue a Apple en su último reporte de resultados?'],
    (t, _) => [
      ..._expect(t.tickersOf('get_earnings').contains('AAPL'), 'no usó get_earnings(AAPL)'),
      ..._expect(t.components.contains('QaEarningsCalendar'), 'sin QaEarningsCalendar: ${t.components}'),
      ..._expect(!_beatRe.hasMatch(t.text), 'dijo superó/no alcanzó sin consenso: ${t.text}'),
      ..._v2Common(t),
    ],
  ),
  _Case(
    'v2-earn-consenso-nvda',
    ['¿Qué ganancias esperan los analistas para el próximo reporte de Nvidia?'],
    (t, _) => [
      ..._expect(t.tickersOf('get_earnings').contains('NVDA'), 'no usó get_earnings(NVDA)'),
      // Un consenso con número solo vale si salió del contexto con citas.
      ..._expect(
        t.calls.any(
              (c) =>
                  c.name == 'get_news' &&
                  c.result['context'] is Map &&
                  (c.result['context'] as Map)['status'] == 'ok',
            ) ||
            !RegExp(r'consenso|analistas esperan|se espera', caseSensitive: false)
                .hasMatch(_proseOf(t)) ||
            RegExp(r'no (tengo|hay|cuento con|encontr)', caseSensitive: false)
                .hasMatch(_proseOf(t)),
        'atribuyó un consenso sin fuente: ${_proseOf(t)}',
      ),
      ..._v2Common(t),
    ],
  ),
  _Case(
    'v2-earn-baba-extranjera',
    ['¿Cómo le fue a Alibaba en su último trimestre?'],
    (t, _) => [
      ..._expect(t.tickersOf('get_earnings').contains('BABA'), 'no usó get_earnings(BABA)'),
      ..._expect(!_beatRe.hasMatch(t.text), 'dijo superó/no alcanzó sin consenso: ${t.text}'),
      ..._v2Common(t),
    ],
  ),
  _Case(
    'v2-fund-margen-ko',
    ['¿Qué margen neto tiene Coca-Cola?'],
    (t, _) => [
      ..._expect(t.tickersOf('get_fundamentals').contains('KO'), 'no usó get_fundamentals(KO)'),
      ..._v2Common(t),
    ],
  ),
  _Case(
    'v2-fund-pe-msft',
    ['¿Está cara Microsoft? ¿Qué P/E tiene?'],
    (t, _) => [
      ..._expect(t.tickersOf('get_fundamentals').contains('MSFT'), 'no usó get_fundamentals(MSFT)'),
      ..._expect(
        !RegExp(r'forward|proyectado|beta', caseSensitive: false).hasMatch(t.text),
        'usó un dato que la SEC no tiene: ${t.text}',
      ),
      ..._v2Common(t),
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
      // EVAL_NEWS_V2=1: SOLO los casos v2, con SEC / búsqueda web / GDELT
      // por las edge functions locales (mismo JWT que el proxy).
      final newsV2 = Platform.environment['EVAL_NEWS_V2'] == '1';
      if (newsV2) {
        dotenv.testLoad(
          fileInput: File('assets/env/.env.development').readAsStringSync(),
        );
        final edge = PortyEdgeClient(
          baseUrl: proxy.endpoint.toString().replaceFirst(RegExp(r'/ai-chat$'), ''),
          accessToken: () async => jwt,
          anonKey: Platform.environment['EVAL_ANON_KEY'],
        );
        final quotes = QuoteRepositoryImpl(
          remoteDataSource: YahooQuoteRemoteDataSource(),
        );
        realData = AssistantDataSources(
          newsProvider: NewsProvider.v2,
          quoteRepository: quotes,
          preferences: FakePreferences(),
          earnings: SecEarningsFetcher(client: edge),
          fundamentals: SecFundamentalsFetcher(quotes: quotes, client: edge),
          news: NewsFetcher(headlines: GdeltHeadlinesRepositoryImpl(client: edge)),
          newsContext: NewsContextClient(client: edge),
        );
      }
      final cases = newsV2 ? _newsV2Cases : _cases;
      final report = <Map<String, Object?>>[];
      var failures = 0;

      final only = Platform.environment['EVAL_ONLY'];
      for (final c in cases.where(
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
          model: env['OPENAI_MODEL'] ?? 'gpt-6-luna',
          httpClient: recorder,
        );
        // Una por caso, como en la app (vive toda la conversación): los
        // casos de varios turnos necesitan el plan del turno anterior.
        final caseData = realData ?? fakeDataSources(
          dividendYahoo: _AnyTickerDividends(),
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
                );
        final logs = <_TurnLog>[];
        var courtesyLeft = c.weeklyFree;
        for (var i = 0; i < c.turns.length; i++) {
          final log = _TurnLog();
          final ctx = AssistantToolContext(
            tier: c.tier,
            summary: heldSummary,
            data: caseData,
            newsProvider: newsV2 ? NewsProvider.v2 : NewsProvider.legacy,
            saveMemory:
                (content, category, {replacesId}) async => UserMemory(
                  id: 'eval-memory',
                  content: content,
                  category: category,
                  source: UserMemorySource.porty,
                  updatedAt: DateTime.now(),
                ),
            deleteMemory: (_) async {},
            // Plan y lista fijos para los casos plan-* y watchlist-*.
            loadAllocationPlan:
                () async => const AllocationPlan(
                  targets: {'AAPL': 70, 'NVDA': 30},
                ),
            loadWatchlist:
                () async => [
                  {
                    'ticker': 'AMZN',
                    'price': 182.5,
                    'day_change_pct': -1.8,
                    'since_added_pct': 6.4,
                    'alerts_on': true,
                  },
                ],
            loadPriceAlerts:
                () async => [
                  {
                    'id': 'alert-voo',
                    'symbol': 'VOO',
                    'condition': 'above',
                    'target': 750,
                    'status': 'active',
                  },
                ],
            loadAppSettings:
                () async => {
                  'theme': 'system',
                  'notify_earnings': true,
                  'currency': 'USD',
                },
            loadConnectedAccounts:
                () async => {'etoro': 'connected', 'binance': 'not_connected'},
            loadAccountOverview:
                () async => {
                  'plan': 'premium',
                  'queries_used_this_month': 120,
                  'queries_limit_this_month': 500,
                },
            loadWeeklyReport:
                () async => {
                  'week': '2026-10-19',
                  'change_pct': 2.4,
                  'change_abs': 312.5,
                  'value_end': 13350,
                  'movers': [
                    {'ticker': 'NVDA', 'pct': 6.1},
                    {'ticker': 'AAPL', 'pct': -1.2},
                  ],
                  'reading': 'Semana buena, empujada por NVDA.',
                },
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
            log.truncatedRounds =
                service.log.currentTurn?.truncatedRounds ?? 0;
            // EVAL_DUMP_DIR: guarda la respuesta cruda de los turnos que
            // llegaron al tope de salida, para ver en qué se desbocó.
            final dumpDir = Platform.environment['EVAL_DUMP_DIR'];
            if (log.truncatedRounds > 0 && dumpDir != null) {
              Directory(dumpDir).createSync(recursive: true);
              File('$dumpDir/${c.id}_$i.txt').writeAsStringSync(raw);
            }
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
                  final shown = component?.properties['text'];
                  if (type == 'QaAnswerText' && shown is String) {
                    log.answerText += shown;
                  }
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
          'truncated_rounds': logs.fold<int>(
            0,
            (s, l) => s + l.truncatedRounds,
          ),
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
      print('EVALS: ${report.length - failures}/${report.length} passed');
    },
    skip:
        enabled
            ? false
            : 'set RUN_ASSISTANT_EVALS=1 to run against the real model',
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

/// Yahoo con dividendos para cualquier ticker que elija el modelo (ETF al
/// 3,6%; algunas acciones conocidas como acción al 2,9%).
class _AnyTickerDividends extends FakeYahooProxy {
  static const _stocks = {'KO', 'JNJ', 'PG', 'PEP', 'T', 'VZ', 'O', 'MO', 'ABBV', 'XOM', 'CVX', 'MCD', 'PFE'};

  @override
  Future<Map<String, dynamic>?> quoteSummary(
    String symbol,
    List<String> modules,
  ) async {
    final stock = _stocks.contains(symbol.toUpperCase());
    return dividendQuoteSummary(
      name: '$symbol Fund',
      etf: !stock,
      yieldFraction: stock ? 0.029 : 0.036,
    );
  }
}
