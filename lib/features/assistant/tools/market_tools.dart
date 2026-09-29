import 'package:portfolio_assistant/features/assistant/data/market/ticker_quote_builder.dart';
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

/// Valuación, rentabilidad y dividendo (Gold).
class GetFundamentalsTool implements DataTool {
  GetFundamentalsTool(this.ctx);

  final AssistantToolContext ctx;

  @override
  String get name => 'get_fundamentals';

  @override
  String get description =>
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

  @override
  Map<String, Object?> get parameters => _tickersParams;

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final tickers = ToolArgs.tickers(args);
    if (tickers.isEmpty) return ToolArgs.invalid();
    if (!ctx.premiumDataAllowed) return ctx.locked('gold');
    return {...await ctx.data.fundamentals.fetch(tickers), 'as_of': ctx.asOf};
  }
}

/// Próximo reporte y último resultado (Gold).
class GetEarningsTool implements DataTool {
  GetEarningsTool(this.ctx);

  final AssistantToolContext ctx;

  @override
  String get name => 'get_earnings';

  @override
  String get description =>
      'Earnings for 1-3 tickers: next_report (date ISO, date_label, '
      'fiscal_period_label, timing_label?, eps_estimate = market CONSENSUS '
      'for the upcoming report, may be absent), latest_result (last '
      'reported quarter: report_date_label? or fiscal_period_label, '
      'eps_actual, eps_estimate, surprise_pct, beat) and history (up to 4 '
      'reported quarters, OLDEST first: fiscal_period_label, eps_actual, '
      'eps_estimate, surprise_pct, beat). Use it for "¿cuándo reporta X?", '
      'expected earnings / EPS consensus, or how the last report(s) went. '
      'status: ok | empty | failed | locked.';

  @override
  Map<String, Object?> get parameters => _tickersParams;

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final tickers = ToolArgs.tickers(args);
    if (tickers.isEmpty) return ToolArgs.invalid();
    if (!ctx.premiumDataAllowed) return ctx.locked('gold');
    return {...await ctx.data.earnings.fetch(tickers), 'as_of': ctx.asOf};
  }
}

/// Titulares recientes (Gold). Pesa 3 en la cuota del turno.
class GetNewsTool implements DataTool {
  GetNewsTool(this.ctx);

  final AssistantToolContext ctx;

  @override
  String get name => 'get_news';

  @override
  String get description =>
      'Up to 3 of the most relevant real headlines (last 7-14 days, reputable '
      'outlets first) for 1-3 tickers: ticker, title, snippet (may be empty), '
      'url (copy it verbatim into the widget: the app uses it '
      'for the image and link), source, published_at. Use it when the user asks '
      'for news, or asks WHY a ticker moved (the only allowed source of '
      'causes). status: ok | empty (no recent news) | failed | locked.';

  @override
  Map<String, Object?> get parameters => _tickersParams;

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final tickers = ToolArgs.tickers(args);
    if (tickers.isEmpty) return ToolArgs.invalid();
    if (!ctx.premiumDataAllowed) {
      return ctx.locked('gold', PaywallReason.newsRequiresGold);
    }
    return {...await ctx.data.news.fetch(tickers), 'as_of': ctx.asOf};
  }
}
