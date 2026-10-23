import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/allocation/domain/allocation_plan.dart';
import 'package:portfolio_assistant/features/assistant/tools/answer_guide.dart';
import 'package:portfolio_assistant/features/assistant/tools/manage_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/tool_args.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/assistant/tools/action_tools.dart';
import 'package:uuid/uuid.dart';

/// El plan de cartera y la lista de seguimiento desde el chat (siguiente
/// paso de docs/superpowers/plans/2026-10-16-porty-siguiente-nivel.md).
///
/// - `get_allocation_plan`: el plan del usuario, el desvío de cada ticker y,
///   si pide, cómo repartir un aporte. Solo lectura: el plan se edita en
///   su pantalla.
/// - `get_watchlist`: la lista con precio, día y desde que se agregó.
/// - `propose_watch`: prepara seguir un ticker; el usuario lo confirma en
///   la card `QaActionProposal` (como las demás acciones de Porty).
abstract final class PlanTools {
  static const getAllocationPlan = 'get_allocation_plan';
  static const getWatchlist = 'get_watchlist';
  static const proposeWatch = 'propose_watch';

  static const names = {getAllocationPlan, getWatchlist, proposeWatch};

  static List<DataTool> build(AssistantToolContext ctx) => [
    GetAllocationPlanTool(ctx),
    GetWatchlistTool(ctx),
    ProposeWatchTool(ctx),
  ];
}

double _round1(double v) => (v * 10).roundToDouble() / 10;

/// Cómo responder con cada resultado (ver [AnswerGuide]). En inglés, como el
/// resto de las instrucciones al modelo.
abstract final class PlanGuides {
  static const planOk =
      'QaAllocationPlan (no props: the app draws every ticker, bar and '
      'amount from this result) + QaAnswerText with 1-2 sentences, no '
      'bullets: the biggest gap from off_plan (or that everything is within '
      'the drift_threshold margin); with contribution, that the amount goes '
      'mostly to what is below the plan, buying only. Don\'t repeat the '
      'rows. The plan is the user\'s own targets: say "para acercarte a tu '
      'plan"; never "te conviene" or "comprá", never judge a target.';
  static const planEmpty =
      'QaAnswerText: they have no plan yet; offer to set it up right here '
      '(ask how much they want of each investment) or in Ajustes → Mi plan '
      'de cartera.';
  static const watchlistOk =
      'QaWatchlist (no props: the app draws every ticker and number) + '
      'QaAnswerText with ONE sentence on what stands out (the biggest move '
      'today), no list.';
  static const watchlistEmpty =
      'QaAnswerText: their watchlist is empty; they can ask you to follow a '
      'ticker ("seguí AMZN").';
  static const addHeld =
      'QaAnswerText: they already own it, so it doesn\'t go on the '
      'watchlist; offer a price alert instead.';
  static const addAlready = 'QaAnswerText: it is already on their watchlist.';
  static const addLimit =
      'QaAnswerText: their plan allows up to `limit` tickers on the watchlist.';
  static const addUnknown =
      'Check the ticker with search_symbol, or ask which company they mean.';
}

class GetAllocationPlanTool implements DataTool {
  GetAllocationPlanTool(this.ctx);

  final AssistantToolContext ctx;

  @override
  String get name => PlanTools.getAllocationPlan;

  @override
  String get description =>
      'The user\'s PORTFOLIO PLAN (target % per ticker that THEY set) vs. '
      'today\'s weights: rows {ticker, current_pct, target_pct, drift_pts}, '
      'drift_threshold (points), off_plan (tickers beyond the threshold). '
      'contribution_usd → also how to split that amount to get closer to '
      'their plan, buying only (split: {ticker, amount_usd}); pass it only '
      'when they name an amount. Read-only. status: ok | empty | locked '
      '(Premium) | failed.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'contribution_usd': {
        'type': 'number',
        'description':
            'Only if the user asks how to split an amount they will add '
            '("¿cómo reparto 500?").',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    if (!ctx.allows(PlanFeature.allocationPlan)) {
      return ctx.lockedFeature(PlanFeature.allocationPlan);
    }
    final load = ctx.loadAllocationPlan;
    if (load == null) return {'status': 'failed', 'reason': 'unavailable'};
    final AllocationPlan? plan;
    try {
      plan = await load();
    } catch (_) {
      return {'status': 'failed', 'reason': 'unavailable'};
    }
    if (plan == null || plan.isEmpty) {
      return AnswerGuide.attach({
        'status': 'empty',
        'as_of': ctx.asOf,
      }, PlanGuides.planEmpty);
    }

    final values = ctx.holdingsByTicker;
    final rows = AllocationMath.rows(values: values, targets: plan.targets);
    final amount = ToolArgs.number(args, 'contribution_usd');
    final split =
        amount != null && amount > 0 && plan.sumsTo100
            ? AllocationMath.contribution(
              values: values,
              targets: plan.targets,
              amount: amount,
            )
            : const <String, double>{};
    return AnswerGuide.attach({
      'status': 'ok',
      'drift_threshold': plan.driftThreshold,
      'weekly_alert': plan.notify,
      'max_drift_pts': _round1(AllocationMath.maxDrift(rows)),
      'portfolio_value_usd': _round1(
        values.values.where((v) => v > 0).fold(0.0, (a, b) => a + b),
      ),
      'off_plan': [
        for (final r in rows)
          if (r.drift.abs() >= plan.driftThreshold) r.ticker,
      ],
      'rows': [
        for (final r in rows)
          {
            'ticker': r.ticker,
            'current_pct': _round1(r.currentPct),
            'target_pct': _round1(r.targetPct),
            'drift_pts': _round1(r.drift),
          },
      ],
      if (amount != null && amount > 0)
        'contribution': {
          'amount_usd': amount,
          'split': [
            for (final e
                in split.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
              {'ticker': e.key, 'amount_usd': e.value},
          ],
        },
      'as_of': ctx.asOf,
    }, PlanGuides.planOk);
  }
}

class GetWatchlistTool implements DataTool {
  GetWatchlistTool(this.ctx);

  final AssistantToolContext ctx;

  @override
  String get name => PlanTools.getWatchlist;

  @override
  String get description =>
      'The user\'s WATCHLIST (tickers they follow but don\'t own): items '
      '{ticker, price, day_change_pct, since_added_pct, alerts_on}. '
      'status: ok | empty | locked (Premium) | failed.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {},
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    if (!ctx.marketDataAllowed) {
      return ctx.lockedFeature(PlanFeature.marketData);
    }
    final load = ctx.loadWatchlist;
    if (load == null) return {'status': 'failed', 'reason': 'unavailable'};
    try {
      final items = await load();
      return AnswerGuide.attach({
        'status': items.isEmpty ? 'empty' : 'ok',
        'items': items,
        'as_of': ctx.asOf,
      }, items.isEmpty ? PlanGuides.watchlistEmpty : PlanGuides.watchlistOk);
    } catch (_) {
      return {'status': 'failed', 'reason': 'unavailable'};
    }
  }
}

/// Seguir un ticker: prepara una card para que el usuario lo confirme
/// (como `propose_price_alert`); nunca agrega nada. Antes de proponer
/// revisa lo que se sabe sin escribir: que tenga cotización, que no lo siga
/// ya, que no lo tenga en cartera y que le quede lugar en el plan.
class ProposeWatchTool implements DataTool {
  ProposeWatchTool(this.ctx);

  final AssistantToolContext ctx;

  @override
  String get name => PlanTools.proposeWatch;

  @override
  String get description =>
      'Card to confirm a WATCHLIST change: follow a ticker ("seguí AMZN"), '
      'unfollow it, or turn its sharp-move alerts on/off. status: ok | '
      'already_there | not_on_watchlist | no_change | held | limit_reached '
      '| unknown_symbol | locked.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'ticker': {'type': 'string'},
      'action': {
        'type': 'string',
        'enum': ['follow', 'unfollow', 'alerts_on', 'alerts_off'],
      },
    },
    'required': ['ticker'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    if (!ctx.marketDataAllowed) {
      return ctx.lockedFeature(PlanFeature.marketData);
    }
    // Dejar de seguir y los avisos: otra card (ver ProposeWatchlistChange).
    final action = ToolArgs.string(args, 'action') ?? 'follow';
    if (action != 'follow') {
      return ProposeWatchlistChangeTool(ctx).run({
        'ticker': args['ticker'],
        'change': action == 'unfollow' ? 'remove' : action,
      });
    }
    final raw = ToolArgs.string(args, 'ticker');
    final tickers =
        raw == null
            ? const <String>[]
            : ToolArgs.tickers({
              'tickers': [raw],
            }, max: 1);
    if (tickers.isEmpty) {
      return ActionGuides.attachTo({
        'status': 'needs_input',
        'missing': ['ticker'],
      });
    }
    final ticker = tickers.first;
    if (ctx.heldTickers.contains(ticker)) {
      return AnswerGuide.attach({
        'status': 'held',
        'ticker': ticker,
      }, PlanGuides.addHeld);
    }

    final load = ctx.loadWatchlist;
    if (load != null) {
      try {
        final items = await load();
        final symbols = {
          for (final i in items) '${i['ticker'] ?? ''}'.toUpperCase(),
        };
        if (symbols.contains(ticker)) {
          return AnswerGuide.attach({
            'status': 'already_there',
            'ticker': ticker,
          }, PlanGuides.addAlready);
        }
        final limit = PlanMatrix.of(ctx.tier).watchlistLimit;
        if (items.length >= limit) {
          return AnswerGuide.attach({
            'status': 'limit_reached',
            'limit': limit,
          }, PlanGuides.addLimit);
        }
      } catch (_) {
        // Sin la lista no se puede revisar: el alta lo vuelve a controlar.
      }
    }

    final quote = await ctx.data.quoteRepository.getCurrentPrice(ticker);
    final price = quote.fold<double?>((_) => null, (p) => p > 0 ? p : null);
    if (price == null) {
      return AnswerGuide.attach({
        'status': 'unknown_symbol',
        'ticker': ticker,
      }, PlanGuides.addUnknown);
    }
    return ActionGuides.attachTo({
      ...ActionProposal(
        id: const Uuid().v4(),
        kind: ActionKind.watch,
        ticker: ticker,
        price: price,
        priceSource: PriceSource.closeOnDate,
      ).toToolResult(),
      'as_of': ctx.asOf,
    });
  }
}
