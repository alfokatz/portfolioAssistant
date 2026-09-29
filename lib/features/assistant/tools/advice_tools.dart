import 'package:portfolio_assistant/features/assistant/data/invest/invest_candidates_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/tool_args.dart';
import 'package:portfolio_assistant/features/assistant/utils/investor_profile_context.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';

/// Candidatos para una simulación educativa de inversión (Gold).
class GetInvestCandidatesTool implements DataTool {
  GetInvestCandidatesTool(this.ctx);

  final AssistantToolContext ctx;

  static const toolName = 'get_invest_candidates';

  @override
  String get name => toolName;

  @override
  String get description =>
      'Real data for an EDUCATIONAL investment simulation, when the user wants '
      'to invest a budget or asks for ideas of what to buy ("tengo \$500 para '
      'invertir", "¿en qué invierto?", "acciones de energía renovable", '
      '"algo defensivo"). YOU choose the candidates: 2-6 US-listed stocks or '
      'ETFs from ANY industry that fit what the user asked (sector, theme, '
      'budget, their investor profile, diversification vs. their current '
      'holdings in PORTFOLIO_BRIEF) — there is no predefined list. Include '
      'any ticker the user named. NOT for money already invested ("¿cuánto '
      'tengo invertido?" is PORTFOLIO_BRIEF). Returns has_budget, budget_usd, '
      'investor_profile (status missing | complete | stale, risk_tolerance, '
      'horizon, objective), sector_concentration of the current portfolio '
      '(Spanish names), concentration_warning, overweight_sector, and per '
      'candidate: ticker, sector, industry, beta, risk_level (from beta: '
      'defensivo | intermedio | crecimiento, null if unknown), '
      'matches_profile, current_price, week_change_pct, fit_score, fetch_ok. '
      'If a candidate comes back with fetch_ok false, drop it or call again '
      'with another one.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'theme': {
        'type': 'string',
        'description':
            'What the user wants to invest in, in their words ("energía '
            'renovable", "algo defensivo", "ideas en general"). Write it '
            'FIRST, then choose tickers that fit it.',
      },
      'tickers': {
        'type': 'array',
        'description':
            'The 2-6 NEW candidates YOU chose for `theme` from your own '
            'knowledge of listed companies and ETFs (any industry — there is '
            'no predefined list), plus any ticker the user named. Not the '
            'user\'s current holdings unless about_current_holdings is true.',
        'items': {'type': 'string'},
        'maxItems': 6,
      },
      'about_current_holdings': {
        'type': 'boolean',
        'description':
            'true only when the user asks about adding to stocks they '
            'already hold ("¿sumo más AAPL?").',
      },
      'budget_usd': {
        'type': 'number',
        'description':
            'The amount the user said they want to invest, in USD ("tengo '
            '\$500 para invertir" → 500, "con 2 mil dólares" → 2000). Always '
            'pass it when the user stated an amount in this conversation; '
            'omit it only if they never did — never invent it or use their '
            'portfolio value.',
      },
    },
    'required': ['theme', 'tickers'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    if (!ctx.adviceAllowed) {
      return ctx.locked('gold', PaywallReason.modeLocked);
    }
    final theme = ToolArgs.string(args, 'theme');
    final tickers = ToolArgs.tickers(
      args,
      max: InvestCandidatesBuilder.maxCandidates,
    );
    // gpt-4.1-mini tiende a "elegir" las tenencias que ve en
    // PORTFOLIO_BRIEF, o a mandar la lista vacía esperando que la tool
    // proponga (verificado en evals). Las sugerencias las elige el modelo,
    // sin lista precargada: se le pide que vuelva a elegir.
    final onlyHoldings =
        tickers.isNotEmpty && tickers.every(ctx.heldTickers.contains);
    if (tickers.isEmpty ||
        (onlyHoldings && args['about_current_holdings'] != true)) {
      return {
        'status': DataTool.needsRetryStatus,
        'theme': theme,
        'message':
            'Choose 2-6 NEW US-listed stocks or ETFs from your own knowledge '
            'that fit this theme — any company or industry, not the user\'s '
            'current holdings — and call get_invest_candidates again with '
            'them.',
      };
    }
    final profile = await ctx.loadInvestorProfile?.call();
    final snapshot = await InvestCandidatesBuilder.build(
      tickers: tickers,
      quoteRepository: ctx.data.quoteRepository,
      profileClient: ctx.data.profileClient,
      budgetUsd: ToolArgs.number(args, 'budget_usd'),
      summary: ctx.summary,
      investorProfile: profile,
      asOf: ctx.now,
    );
    return {'status': 'ok', 'as_of': ctx.asOf, 'theme': theme, ...snapshot};
  }

  /// Aviso de completar/revisar el perfil, según el resultado de la tool.
  static String? profileStatusOf(Map<String, Object?> result) {
    final profile = result['investor_profile'];
    return profile is Map ? profile['status'] as String? : null;
  }
}

/// Meta financiera + proyección lineal y hitos (Gold).
class GetGoalProjectionTool implements DataTool {
  GetGoalProjectionTool(this.ctx);

  final AssistantToolContext ctx;

  static const toolName = 'get_goal_projection';

  @override
  String get name => toolName;

  @override
  String get description =>
      'The user\'s financial GOAL (target amount + date) with a pre-computed '
      'linear projection (required_monthly_savings, months_remaining, '
      'projected_amount_at_date, on_track) and 25/50/75/100% milestones. '
      'Use it when the user states or asks about a savings goal ("en 40 años '
      'quiero tener 1 millón", "¿cuánto tengo que ahorrar por mes?", "¿cómo '
      'va mi meta?"). Pass the amount/date/label the user stated in this '
      'conversation; omitted fields come from their saved goal. If '
      'has_complete_goal is false, "missing" lists what to ask for. Never '
      'recalculate the numbers.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'target_amount': {
        'type': 'number',
        'description': 'Target amount in USD, if the user stated it.',
      },
      'target_date': {
        'type': 'string',
        'description':
            'Target date as YYYY-MM-DD, resolved from what the user said '
            '("en 5 años" → today + 5 years), if they stated one.',
      },
      'goal_label': {
        'type': 'string',
        'description': 'Short name for the goal ("Casa", "Jubilación").',
      },
      'monthly_contribution': {
        'type': 'number',
        'description': 'Monthly contribution in USD, if the user stated it.',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    if (!ctx.adviceAllowed) {
      return ctx.locked('gold', PaywallReason.modeLocked);
    }
    final prefs = ctx.data.preferences;
    final saved = await prefs.getSavedGoal();
    final monthly =
        ToolArgs.number(args, 'monthly_contribution') ??
        await prefs.getMonthlyContribution();
    final profile = await ctx.loadInvestorProfile?.call();
    return {
      'status': 'ok',
      'as_of': ctx.asOf,
      ...GoalProjectionBuilder.build(
        currentPortfolioValue: ctx.summary?.totalValue ?? 0,
        targetAmount: ToolArgs.number(args, 'target_amount'),
        targetDate: ToolArgs.date(args, 'target_date'),
        label: ToolArgs.string(args, 'goal_label'),
        monthlyContribution: monthly,
        savedGoal: saved,
        asOf: ctx.now,
      ),
      'investor_profile': InvestorProfileContext.build(profile, ctx.now),
    };
  }
}

/// Guarda la meta (Gold). Solo cuando el usuario lo pide explícitamente.
class SaveGoalTool implements DataTool {
  SaveGoalTool(this.ctx);

  final AssistantToolContext ctx;

  @override
  String get name => 'save_goal';

  @override
  String get description =>
      'Saves the user\'s financial goal so later questions can use it. Call '
      'it ONLY when the user explicitly asks to save/remember the goal '
      '("guardá esta meta"), with a complete amount and date.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'goal_label': {'type': 'string'},
      'target_amount': {'type': 'number'},
      'target_date': {'type': 'string', 'description': 'YYYY-MM-DD'},
    },
    'required': ['target_amount', 'target_date'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    if (!ctx.adviceAllowed) {
      return ctx.locked('gold', PaywallReason.modeLocked);
    }
    final amount = ToolArgs.number(args, 'target_amount');
    final date = ToolArgs.date(args, 'target_date');
    if (amount == null || amount <= 0 || date == null) {
      return ToolArgs.invalid();
    }
    final label = ToolArgs.string(args, 'goal_label') ?? 'Mi meta';
    await ctx.data.preferences.saveGoal(
      label: label,
      targetAmount: amount,
      targetDate: GoalProjectionBuilder.formatDate(date),
    );
    return {'status': 'ok', 'saved': true};
  }
}
