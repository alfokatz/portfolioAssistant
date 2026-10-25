import 'package:portfolio_assistant/features/assistant/data/market/ticker_quote_builder.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/tool_args.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';

const _tickersSchema = {
  'type': 'array',
  'description': 'US stock tickers, uppercase (e.g. ["AAPL"]). 1 to 3.',
  'items': {'type': 'string'},
  'minItems': 1,
  'maxItems': 3,
};

const _tickersParams = {
  'type': 'object',
  'properties': {'tickers': _tickersSchema},
  'required': ['tickers'],
  'additionalProperties': false,
};

/// Precio actual y variación por período. Tickers en cartera: todos los
/// planes; ajenos: Premium o Gold.
class GetQuoteTool implements DataTool {
  GetQuoteTool(this.ctx);

  final AssistantToolContext ctx;

  @override
  String get name => 'get_quote';

  @override
  String get description =>
      'Current price and % change per period (day, week, month, quarter, '
      'year) for 1-3 US tickers, plus whether a price chart is available and, '
      'for tickers the user holds, their portfolio weight. Use it for any '
      'question about the price, move or evolution of a ticker, including '
      '"why did it move". For the market in general ("¿cómo está el '
      'mercado?") use SPY as the reference. Do NOT call it for conceptual '
      'questions that only use a ticker as an example ("¿qué es un ETF, '
      'como SPY?").';

  @override
  Map<String, Object?> get parameters => _tickersParams;

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final tickers = ToolArgs.tickers(args);
    if (tickers.isEmpty) return ToolArgs.invalid();

    final quotes = await Future.wait(
      tickers.map((ticker) async {
        final held = ctx.heldTickers.contains(ticker);
        if (!held && !ctx.marketDataAllowed) {
          ctx.lockedReasons.add(PaywallReason.marketDataLocked);
          return <String, Object?>{
            'held': false,
            'status': 'locked',
            'required_plan': 'premium',
          };
        }
        final entry = await TickerQuoteBuilder.build(
          ticker: ticker,
          quoteRepository: ctx.data.quoteRepository,
        );
        return <String, Object?>{
          'held': held,
          ...entry,
          if (held) 'weight_pct': _weightPct(ticker),
        };
      }),
    );

    final byTicker = {
      for (var i = 0; i < tickers.length; i++) tickers[i]: quotes[i],
    };
    final statuses = [for (final q in quotes) q['status'] ?? 'ok'];
    return {
      'status':
          statuses.every((s) => s == 'locked')
              ? 'locked'
              : quotes.any((q) => q['fetch_ok'] == true)
              ? 'ok'
              : 'failed',
      'as_of': ctx.asOf,
      'tickers': byTicker,
    };
  }

  double? _weightPct(String ticker) {
    final summary = ctx.summary;
    if (summary == null || summary.totalValue <= 0) return null;
    for (final v in summary.valuations) {
      if (v.position.ticker.toUpperCase() == ticker) {
        return double.parse(
          (v.marketValue / summary.totalValue * 100).toStringAsFixed(2),
        );
      }
    }
    return null;
  }
}

/// Nombre de empresa → ticker (Finnhub `/search`).
class SearchSymbolTool implements DataTool {
  SearchSymbolTool(this.ctx);

  final AssistantToolContext ctx;

  @override
  String get name => 'search_symbol';

  @override
  String get description =>
      'Finds the US ticker for a company NAME ("Apple", "Nvidia", "Mercado '
      'Libre"). Use it ONLY when the user names a company and no ticker is '
      'known from the message or the conversation. Never for greetings, '
      'thanks, single common words, or financial acronyms (ROE, EPS, ETF). '
      'Returns resolved (one ticker), ambiguous (2-4 candidates: ask the user '
      'which one, never guess) or not_found.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description': 'The company name as the user wrote it.',
      },
    },
    'required': ['query'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final query = ToolArgs.string(args, 'query');
    if (query == null) return ToolArgs.invalid();
    final resolution = await ctx.data.tickerResolver.resolve(query);
    final matches = resolution.matches;
    if (resolution.ticker != null) {
      return {'status': 'resolved', 'ticker': resolution.ticker};
    }
    if (matches != null && matches.isNotEmpty) {
      return {
        'status': 'ambiguous',
        'matches': [
          for (final m in matches)
            {'symbol': m.symbol, 'description': m.description},
        ],
      };
    }
    return {'status': 'not_found'};
  }
}

/// Valuación, rentabilidad y dividendo (Gold). Legacy: Finnhub; v2: SEC
/// EDGAR + precio actual.
class GetFundamentalsTool implements DataTool {
  GetFundamentalsTool(this.ctx);

  final AssistantToolContext ctx;

  @override
  String get name => 'get_fundamentals';

  @override
  String get description => ctx.secData ? _secDescription : _legacyDescription;

  static const _legacyDescription =
      'Company fundamentals for 1-3 tickers: company_name, industry, '
      'market_capitalization (millions of USD), shares_outstanding (millions), '
      'pe_ttm, forward_pe, pb, ps_ttm, ev_ebitda_ttm, peg_ttm, beta, roe_ttm, '
      'roa_ttm (%), gross/operating/net_margin_ttm (%), eps_ttm, '
      'eps_growth_ttm_yoy (%), dividend_yield_indicated_annual (ALREADY in %, '
      'e.g. 0.51 = 0,51% — never multiply by 100), dividend_per_share_ttm, '
      'payout_ratio_ttm (%), week_52_high/low, week_52_price_return_daily '
      '(%), average_volume_10_day (millions). Use it for valuation, margins, '
      'dividend, beta, market cap or "fundamentals de X". status: ok | empty '
      '(no data) | failed (could not fetch now) | locked (not in the plan).';

  static const _secDescription =
      'Company fundamentals for 1-3 tickers, from the company\'s own SEC '
      'filings (source SEC EDGAR; data in English — answer in the user\'s '
      'language): company_name, industry, currency, data_period_end, '
      'ttm_basis (last_4_quarters | last_fiscal_year), revenue_ttm_millions, '
      'revenue_growth_ttm_yoy (%), net_income_ttm_millions, eps_ttm, '
      'eps_growth_ttm_yoy (%), gross/operating/net_margin_ttm (%), roe_ttm, '
      'roa_ttm (%), long_term_debt_millions, cash_millions, '
      'shares_outstanding (millions), dividend_per_share_ttm; and, only when '
      'the company reports in USD, computed with the current price: '
      'market_capitalization (millions of USD), pe_ttm, ps_ttm, pb, '
      'ev_ebitda_ttm, dividend_yield_indicated_annual (ALREADY in %, never '
      'multiply by 100), payout_ratio_ttm (%); week_52_high/low (daily '
      'closes). NOT available: forward P/E, PEG, beta — never invent them. '
      'Tickers in not_in_sec do not file with the SEC (say there is no data). '
      'Use it for valuation, margins, growth, debt, dividend or '
      '"fundamentals de X". status: ok | empty | failed | locked.';

  @override
  Map<String, Object?> get parameters => _tickersParams;

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final tickers = ToolArgs.tickers(args);
    if (tickers.isEmpty) return ToolArgs.invalid();
    final locked = ctx.gate(PlanFeature.fundamentals, tickers);
    if (locked != null) return locked;
    final source = await ctx.data.fundamentals();
    return ctx.courtesyTag({...await source.fetch(tickers), 'as_of': ctx.asOf});
  }
}

/// Próximo reporte y último resultado (Gold). Legacy: Finnhub (calendario
/// y consenso); v2: SEC EDGAR (comunicado de resultados, fecha estimada,
/// sin consenso).
class GetEarningsTool implements DataTool {
  GetEarningsTool(this.ctx);

  final AssistantToolContext ctx;

  @override
  String get name => 'get_earnings';

  @override
  String get description => ctx.secData ? _secDescription : _legacyDescription;

  static const _legacyDescription =
      'Earnings for 1-3 tickers: next_report (date ISO, date_label, '
      'fiscal_period_label, timing_label?, eps_estimate = market CONSENSUS '
      'for the upcoming report, may be absent), latest_result (last '
      'reported quarter: report_date_label? or fiscal_period_label, '
      'eps_actual, eps_estimate, surprise_pct, beat) and history (up to 4 '
      'reported quarters, OLDEST first: fiscal_period_label, eps_actual, '
      'eps_estimate, surprise_pct, beat). Use it for "¿cuándo reporta X?", '
      'expected earnings / EPS consensus, or how the last report(s) went. '
      'status: ok | empty | failed | locked.';

  static const _secDescription =
      'Earnings for 1-3 tickers, from SEC filings (source SEC EDGAR; data and '
      'press release in English — answer in the user\'s language): '
      'next_report {date, date_label, estimated: true} is an ESTIMATE from '
      'the company\'s past reporting calendar, never a confirmed date — '
      'always say it is estimated; latest_result (last reported quarter: '
      'fiscal_period_label, report_date_label, eps_actual, eps_yoy_pct, '
      'revenue_millions, revenue_yoy_pct, net_income_millions); history (up '
      'to 4 quarters, OLDEST first, same fields); annual (companies without '
      'quarterly data); press_release.text (the company\'s own earnings '
      'release, truncated: summarize it, quote figures only from it or the '
      'fields). There is NO analyst consensus here: never say a result beat '
      'or missed expectations. If the user needs the confirmed date or the '
      'consensus, call get_news with a `question`. Tickers in not_in_sec do '
      'not file with the SEC. Use it for "¿cuándo reporta X?" or how the '
      'last report(s) went. status: ok | empty | failed | locked.';

  @override
  Map<String, Object?> get parameters => _tickersParams;

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final tickers = ToolArgs.tickers(args);
    if (tickers.isEmpty) return ToolArgs.invalid();
    final locked = ctx.gate(PlanFeature.earnings, tickers);
    if (locked != null) return locked;
    final source = await ctx.data.earnings();
    return ctx.courtesyTag({...await source.fetch(tickers), 'as_of': ctx.asOf});
  }
}

/// Titulares recientes (Gold). v2: titulares de GDELT (medios permitidos) +
/// contexto con citas de la búsqueda web del servidor.
class GetNewsTool implements SlowDataTool {
  GetNewsTool(this.ctx);

  final AssistantToolContext ctx;

  /// v2: la búsqueda web del servidor tarda ~5-11 s (gpt-5-mini con
  /// búsqueda); los titulares se acotan aparte a [headlinesTimeout].
  @override
  Duration get timeout =>
      ctx.secData ? const Duration(seconds: 22) : const Duration(seconds: 8);

  static const headlinesTimeout = Duration(seconds: 10);

  @override
  String get name => 'get_news';

  @override
  String get description =>
      ctx.secData ? _contextDescription : _legacyDescription;

  static const _legacyDescription =
      'Up to 3 of the most relevant real headlines (last 7-14 days, reputable '
      'outlets first) for 1-3 tickers: ticker, title, snippet (may be empty), '
      'url (copy it verbatim into the widget: the app uses it '
      'for the image and link), source, published_at. Use it when the user asks '
      'for news, or asks WHY a ticker moved (the only allowed source of '
      'causes). status: ok | empty (no recent news) | failed | locked.';

  /// v2: "¿por qué se movió mi cartera?" pide las que más movieron, en UNA
  /// búsqueda (una por turno): con 3 quedaba afuera media cartera.
  static const maxContextTickers = 5;

  static const _contextDescription =
      'News for 1-5 tickers (for the whole portfolio: its biggest movers, '
      'in ONE call). news: up to 3 recent headlines from reputable '
      'outlets (ticker, title, url — copy it verbatim into the widget —, '
      'source, published_at; snippet is empty). context: {summary: short '
      'sentences on what happened in the last 7 days and why it matters, '
      'each starting with its ticker (several tickers) and date, from a web '
      'search restricted to reputable outlets; sources: [{title, '
      'url, source}]} — the app shows the sources as links, never paste '
      'URLs in your text. Use it when the user asks for news, or asks WHY a '
      'ticker moved (the only allowed source of causes: base the "why" on '
      'context.summary). Optional question: one specific question about '
      'recent facts no other tool has (the CONFIRMED date of the next '
      'earnings report, the analysts\' consensus, a recent event), answered '
      'from the web with sources. At most ONE call per turn. status: ok | '
      'empty | failed | locked; context.status limit = no more web searches '
      'now (answer with the headlines).';

  @override
  Map<String, Object?> get parameters =>
      ctx.secData
          ? const {
            'type': 'object',
            'properties': {
              'tickers': {
                'type': 'array',
                'description':
                    'US stock or ETF tickers, uppercase (e.g. ["AAPL"]). 1 '
                    'to 5.',
                'items': {'type': 'string'},
                'minItems': 1,
                'maxItems': maxContextTickers,
              },
              'question': {
                'type': 'string',
                'description':
                    'Optional. A specific question, in Spanish, about recent '
                    'facts (e.g. "¿Cuándo presenta NVDA sus próximos '
                    'resultados? ¿Qué espera el consenso?").',
              },
            },
            'required': ['tickers'],
            'additionalProperties': false,
          }
          : _tickersParams;

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final tickers = ToolArgs.tickers(
      args,
      max: ctx.secData ? maxContextTickers : 3,
    );
    if (tickers.isEmpty) return ToolArgs.invalid();
    final locked = ctx.gate(PlanFeature.news, tickers);
    if (locked != null) return locked;
    final news = await ctx.data.news();
    if (!ctx.secData) {
      return ctx.courtesyTag({...await news.fetch(tickers), 'as_of': ctx.asOf});
    }

    final question = ToolArgs.string(args, 'question');
    // GDELT admite un pedido cada ~5 s para todo Porty: si tarda, los
    // titulares faltan pero el contexto con citas llega igual.
    final headlinesF = news
        .fetch(tickers)
        .timeout(
          headlinesTimeout,
          onTimeout: () => const {'status': 'failed', 'news': []},
        );
    Map<String, Object?> context;
    if (ctx.newsContextCalls >= 1) {
      context = const {'status': 'limit', 'reason': 'turn_limit'};
    } else {
      ctx.newsContextCalls++;
      final found = await Future.wait(tickers.map(news.companyName));
      final names = <String, String>{
        for (var i = 0; i < tickers.length; i++)
          if (found[i] != null) tickers[i]: found[i]!,
      };
      context = await ctx.data.newsContext.fetch(
        tickers,
        names: names,
        question: question,
      );
    }
    final headlines = await headlinesF;
    final ok = headlines['status'] == 'ok' || context['status'] == 'ok';
    return ctx.courtesyTag({
      ...headlines,
      'status':
          ok
              ? 'ok'
              : context['status'] == 'locked'
              ? 'locked'
              : context['status'] == 'empty' || headlines['status'] == 'empty'
              ? 'empty'
              : 'failed',
      'context': context,
      'as_of': ctx.asOf,
    });
  }
}

/// Qué tiene adentro un ETF o fondo (10 posiciones principales, sectores,
/// clase de activo, costo). Como el precio: ETFs en cartera, todos los
/// planes; ajenos, Premium o Gold.
class GetEtfHoldingsTool implements DataTool {
  GetEtfHoldingsTool(this.ctx);

  final AssistantToolContext ctx;

  static const toolName = 'get_etf_holdings';

  @override
  String get name => toolName;

  @override
  String get description =>
      'What an ETF or mutual fund holds, for 1-3 fund tickers: fund_name, '
      'fund_family, category, expense_ratio_pct, total_assets_usd, '
      'top_holdings (its 10 largest positions: symbol, name, weight_pct — '
      'NOT the full portfolio), top_holdings_weight_pct (their combined '
      'weight), sectors (sector already in Spanish, weight_pct, largest '
      'first), stock/bond/cash_position_pct. All percentages are ALREADY in '
      '%. Use it for "¿qué acciones tiene XLF?", "¿en qué invierte VOO?", '
      '"¿cuánto pesa Apple en QQQ?", sector exposure or overlap between '
      'funds. Tickers in not_funds are stocks (no holdings to show). '
      'status: ok | empty | failed | locked.';

  @override
  Map<String, Object?> get parameters => _tickersParams;

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final tickers = ToolArgs.tickers(args);
    if (tickers.isEmpty) return ToolArgs.invalid();
    final allowed = [
      for (final t in tickers)
        if (ctx.marketDataAllowed || ctx.heldTickers.contains(t)) t,
    ];
    if (allowed.isEmpty) return ctx.lockedFeature(PlanFeature.marketData);
    final lockedTickers = [
      for (final t in tickers)
        if (!allowed.contains(t)) t,
    ];
    return {
      ...await ctx.data.etfHoldings.fetch(allowed),
      if (lockedTickers.isNotEmpty) ...{
        'locked_tickers': lockedTickers,
        'required_plan': ctx.requiredPlanFor(PlanFeature.marketData),
      },
      'as_of': ctx.asOf,
    };
  }
}

/// Dividendos de acciones Y ETFs (Yahoo): rendimiento, pago anual por
/// acción, fecha ex-dividendo. Tickers en cartera: todos los planes;
/// ajenos: Premium o Gold (como el precio).
class GetDividendsTool implements DataTool {
  GetDividendsTool(this.ctx);

  final AssistantToolContext ctx;

  static const toolName = 'get_dividends';

  @override
  String get name => toolName;

  @override
  String get description =>
      'Dividend data for 1-6 US stocks or ETFs (Yahoo): kind (etf|stock), '
      'name, price, dividend_yield_pct (ALREADY in %, 0 = pays none), '
      'dividend_per_share_annual, payout_ratio_pct, five_year_avg_yield_pct, '
      'ex_dividend_date. Use it for ANY dividend or yield question ("¿cuánto '
      'paga de dividendos?", "¿qué rendimiento tiene SCHD?"), also for ETFs '
      '— never say a dividend is unavailable without calling it.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'tickers': {
        'type': 'array',
        'description': 'US stock or ETF tickers, uppercase. 1 to 6.',
        'items': {'type': 'string'},
        'minItems': 1,
        'maxItems': 6,
      },
    },
    'required': ['tickers'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final tickers = ToolArgs.tickers(args, max: 6);
    if (tickers.isEmpty) return ToolArgs.invalid();
    final allowed = [
      for (final t in tickers)
        if (ctx.heldTickers.contains(t) || ctx.marketDataAllowed) t,
    ];
    final locked = [
      for (final t in tickers)
        if (!allowed.contains(t)) t,
    ];
    if (allowed.isEmpty) {
      ctx.lockedReasons.add(PaywallReason.marketDataLocked);
      return {'status': 'locked', 'required_plan': 'premium'};
    }
    final fetched = await ctx.data.dividends.fetch(allowed);
    return {
      ...fetched,
      'as_of': ctx.asOf,
      if (locked.isNotEmpty) 'locked_tickers': locked,
    };
  }
}
