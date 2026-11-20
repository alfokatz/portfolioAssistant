import 'package:portfolio_assistant/config/translate/app_language.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/tools/answer_guide.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/market_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/tool_args.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';

/// Búsqueda web, para lo que ninguna otra tool cubre — sobre todo el precio
/// de lo que el usuario quiere comprar ("la MacBook Neo rosa"). Corre en el
/// servidor (`web-search`): caché compartida y tope diario por plan.
class SearchWebTool implements DataTool {
  SearchWebTool(this.ctx);

  final AssistantToolContext ctx;

  static const toolName = 'search_web';

  @override
  String get name => toolName;

  @override
  String get description =>
      'Searches the web for a personal-finance FACT no other tool has: '
      'what something the user wants costs (a product, a trip, a party, a '
      'service: "MacBook Neo rosa", "pasaje a Madrid", "fiesta para 200 '
      'personas en Buenos Aires"), an exchange rate ("dólar oficial hoy '
      'Argentina") to convert amounts they said in another currency, or a '
      'fee, rate or cost they ask about. Use it BEFORE asking the user for '
      'a fact like that; ask only if it finds nothing reliable. Returns answer (a '
      'short summary) and sources [{title, url}]. NEVER for stock prices, '
      'news or company data (use the market tools), never for off-topic '
      'questions, and only once per thing per conversation (reuse the '
      'result). status limit = daily or monthly search limit reached: ask the '
      'user for the price instead.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description':
            'Specific search, in Spanish or English, with the exact product '
            'or item ("precio MacBook Neo rosa en USD").',
      },
    },
    'required': ['query'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final query = ToolArgs.string(args, 'query');
    if (query == null || query.length < 3) return ToolArgs.invalid();
    final clipped = query.length > 200 ? query.substring(0, 200) : query;
    final result = {
      ...await ctx.data.webSearch.search(clipped),
      'as_of': ctx.asOf,
    };
    // Tope mensual: es de costo, no una oferta de plan (sin paywall).
    return result['reason'] == monthlyLimitReason
        ? AnswerGuide.attach(result, monthlyLimitGuide)
        : result;
  }

  static const monthlyLimitReason = 'monthly_limit';

  static const monthlyLimitGuide =
      'ask the user for the fact instead; do not mention plans.';
}

/// "Qué dice cada medio" sobre UN ticker o UN tema (edge function
/// `news-compare`, spec 2026-11-20 §3.6): en qué coinciden y en qué difieren
/// distintos medios, con medio y link en cada fila. La card
/// (`QaSourceComparison`) la dibuja la app desde este resultado.
///
/// El plan se aplica acá, antes de llamar: tickers con `allowsNewsFor`
/// (Premium solo los de su cartera, Gold todos) y temas solo con Gold. Si
/// no pasa, `locked` + `required_plan`. Comparte con `get_news` el tope de
/// una búsqueda con citas por turno (`ctx.newsContextCalls`).
class CompareSourcesTool implements SlowDataTool {
  CompareSourcesTool(this.ctx, {this.fetchTimeout = defaultFetchTimeout});

  final AssistantToolContext ctx;

  /// Una búsqueda con citas tarda 10-30 s (el cliente HTTP corta a los 30):
  /// el tope de la tool queda un poco por encima del de la llamada.
  @override
  Duration get timeout => const Duration(seconds: 36);

  /// Tope de la llamada a `news-compare`: si no llega, la tool responde
  /// `failed` en vez de colgar el turno.
  final Duration fetchTimeout;

  static const defaultFetchTimeout = Duration(seconds: 32);

  static const toolName = 'compare_sources';

  @override
  String get name => toolName;

  @override
  String get description =>
      'How different outlets cover ONE ticker or ONE topic id '
      '(screen_context.news.topic_id): "qué dice cada medio", "¿coinciden?". '
      'Not for what happened (get_news). Returns points [{kind: '
      'agree|differ|only, text, source_ids}], outlets, sources. status: ok | '
      'empty | insufficient_sources | locked | limit | failed.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'ticker': {'type': 'string', 'description': 'One of ticker or topic.'},
      'topic': {'type': 'string'},
    },
    'additionalProperties': false,
  };

  /// `reason` de un `failed` con el interruptor del brief apagado.
  static const disabledReason = 'disabled';

  static const okGuide =
      'QaSourceComparison (no props: the app draws it) + QaAnswerText with '
      '1-2 sentences on where the outlets agree or differ, naming outlets '
      'only from outlets; never say which one is right; no advice; no '
      'numbers that are not in points.';

  static const noCoverageGuide =
      'QaAnswerText only: there is not enough recent coverage from different '
      'outlets to compare; say it in one sentence and offer the headlines '
      '(get_news). Do not name outlets.';

  static const limitGuide =
      'The comparison limit was reached for now: say it in one short clause '
      'and offer the headlines (get_news) if the plan has them; do not '
      'mention plans.';

  static const disabledGuide =
      'Comparing outlets is not available right now: answer with get_news '
      'instead; do not mention this.';

  static final _topic = RegExp(r'^[a-z0-9_]{2,40}$');

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final rawTicker = ToolArgs.string(args, 'ticker');
    final ticker =
        rawTicker == null
            ? null
            : ToolArgs.tickers({
              'tickers': [rawTicker],
            }, max: 1).firstOrNull;
    final rawTopic = ToolArgs.string(args, 'topic');
    final topic = rawTopic != null && _topic.hasMatch(rawTopic) ? rawTopic : null;
    // Exactamente uno de los dos (y bien escrito).
    if ((ticker == null) == (topic == null)) return ToolArgs.invalid();

    final locked = _gate(ticker);
    if (locked != null) return locked;

    if (ctx.newsContextCalls >= 1) {
      return AnswerGuide.attach({
        'status': 'limit',
        'reason': 'turn_limit',
        'as_of': ctx.asOf,
      }, limitGuide);
    }
    ctx.newsContextCalls++;

    final fetched = await ctx.data.sourceCompare
        .fetch(
          ticker: ticker,
          topicId: topic,
          storyUrl: _storyUrl(ticker: ticker, topic: topic),
          lang: AppLanguage.detect(
            ctx.userQuestion ?? '',
            fallback: ctx.appLanguage,
          ),
          turnId: ctx.turnId?.call(),
        )
        .timeout(
          fetchTimeout,
          onTimeout: () => const {'status': 'failed', 'reason': 'timeout'},
        );

    // `as_of` es de ahora; cuándo se hizo la comparación (puede venir de la
    // caché del servidor) va aparte.
    final result = <String, Object?>{
      ...fetched,
      if (fetched['as_of'] != null) 'searched_at': fetched['as_of'],
      'as_of': ctx.asOf,
    };
    return switch (result['status']) {
      'ok' => AnswerGuide.attach(result, okGuide),
      'empty' || 'insufficient_sources' => AnswerGuide.attach(
        result,
        noCoverageGuide,
      ),
      'limit' => AnswerGuide.attach(
        result,
        result['reason'] == GetNewsTool.monthlyLimitReason
            ? GetNewsTool.monthlyLimitGuide
            : limitGuide,
      ),
      'failed' when result['reason'] == disabledReason => AnswerGuide.attach(
        result,
        disabledGuide,
      ),
      _ => result,
    };
  }

  /// El plan, antes de llamar. `null` = pasa. Como `get_news`: Free queda
  /// fuera (Premium si el ticker es suyo, Gold si no), y a Premium con un
  /// ticker que no tiene no se le corta el turno: la app agrega el bloque
  /// de Gold.
  Map<String, Object?>? _gate(String? ticker) {
    if (ticker == null) {
      return ctx.allows(PlanFeature.news)
          ? null
          : ctx.lockedFeature(PlanFeature.news);
    }
    final held = ctx.heldTickers.contains(ticker);
    if (PlanMatrix.allowsNewsFor(ctx.tier, held: held)) return null;
    if (!ctx.allows(PlanFeature.heldNews)) {
      return ctx.lockedFeature(held ? PlanFeature.heldNews : PlanFeature.news);
    }
    ctx.lockedFeatures.add(PlanFeature.news);
    return {
      ...ctx.locked(
        ctx.requiredPlanFor(PlanFeature.news),
        PaywallReason.goldRequired,
      ),
      'reason': GetNewsTool.notHeldReason,
    };
  }

  /// El link de la noticia desde la que abrió el chat, si la comparación es
  /// de ESA noticia (mismo ticker o tema): el servidor enfoca la búsqueda y
  /// descarta el link si su medio no está en la allowlist.
  String? _storyUrl({String? ticker, String? topic}) {
    final news = ctx.screenContext?['news'];
    if (news is! Map) return null;
    final same =
        ticker != null
            ? '${news['ticker'] ?? ''}'.toUpperCase() == ticker
            : '${news['topic_id'] ?? ''}' == topic;
    final url = '${news['url'] ?? ''}';
    return same && url.startsWith('https://') ? url : null;
  }
}
