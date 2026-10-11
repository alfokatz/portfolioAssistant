import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/invest_candidates_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/buy_plan_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/tool_args.dart';
import 'package:portfolio_assistant/features/assistant/utils/investor_profile_context.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

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
    if (!ctx.allows(PlanFeature.investSimulation)) {
      return ctx.lockedFeature(PlanFeature.investSimulation);
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
      // El reintento se arma de cero: sin repetir el presupuesto acá, el
      // modelo lo pierde en la segunda llamada (visto en evals: 2 de 3).
      final budget = ToolArgs.number(args, 'budget_usd');
      return {
        'status': DataTool.needsRetryStatus,
        'theme': theme,
        if (budget != null) 'budget_usd': budget,
        'message':
            'Choose 2-6 NEW US-listed stocks or ETFs from your own knowledge '
            'that fit this theme — any company or industry, not the user\'s '
            'current holdings — and call get_invest_candidates again with '
            'them${budget != null ? ', keeping the same budget_usd' : ''}.',
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

/// Meta financiera + plan de ahorro con interés compuesto (Premium).
class GetGoalProjectionTool implements DataTool {
  GetGoalProjectionTool(this.ctx);

  final AssistantToolContext ctx;

  static const toolName = 'get_goal_projection';

  @override
  String get name => toolName;

  @override
  String get description =>
      'The user\'s financial GOAL (target amount + date: retirement, or '
      'something to BUY like a laptop, a car, a trip, a house deposit) '
      'with a pre-computed SAVINGS PLAN: compound growth in today\'s dollars '
      '(after inflation), a suggested allocation for their risk, required '
      'monthly savings in pessimistic/base/optimistic scenarios, what they '
      'would need without investing, what-if horizons and, for retirement or '
      'an income goal, the two ways to collect it (living off dividends vs. '
      'withdrawing 4% a year) with the capital each needs. Use it when the user states '
      'or asks about a savings goal, a purchase or retirement ("en 20 años '
      'quiero tener 500 mil", "¿cuánto tengo que ahorrar por mes?", "quiero '
      'comprarme una compu de 1200 en un año", "quiero jubilarme cobrando '
      '3000 por mes", "¿cómo va mi meta?"). Pass only what the user '
      'stated in this conversation; omitted fields come from their saved '
      'goal and investor profile. If has_complete_goal is false, "missing" '
      'lists what to ask for. Never recalculate the numbers.';

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
      'is_retirement': {
        'type': 'boolean',
        'description': 'true when the goal is retiring (jubilarse/retirarse).',
      },
      'goal_type': {
        'type': 'string',
        'enum': ['retirement', 'purchase', 'other'],
        'description':
            'purchase = buying something concrete (computer, phone, car, '
            'trip, wedding, house deposit): starts from 0 unless '
            'current_savings is stated, and under 3 years the plan uses '
            'cash and short-term bonds, no stocks.',
      },
      'monthly_contribution': {
        'type': 'number',
        'description':
            'Monthly amount in USD the user said they can save, if stated.',
      },
      'current_savings': {
        'type': 'number',
        'description':
            'USD the user said they already have for this goal, if stated '
            '(default: their portfolio value; 0 for a purchase).',
      },
      'desired_monthly_income': {
        'type': 'number',
        'description':
            'Retirement only: monthly income in USD the user wants to live '
            'on, if stated instead of a target amount.',
      },
      'income_strategy': {
        'type': 'string',
        'enum': ['dividends', 'withdrawal'],
        'description':
            'With desired_monthly_income: how they would collect it. Only '
            'if the user chose one ("rehacelo retirando el 4%"); default '
            'dividends (living off dividends, capital untouched).',
      },
      'risk': {
        'type': 'string',
        'enum': ['conservative', 'moderate', 'aggressive'],
        'description':
            'Only if the user asked for this risk in the conversation '
            '("soy más conservador", "rehacelo agresivo"); otherwise omit '
            'and their investor profile is used.',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    if (!ctx.allows(PlanFeature.goals)) {
      return ctx.lockedFeature(PlanFeature.goals);
    }
    final prefs = ctx.data.preferences;
    final saved = await prefs.getSavedGoal();
    final monthly =
        ToolArgs.number(args, 'monthly_contribution') ??
        await prefs.getMonthlyContribution();
    final profile = await ctx.loadInvestorProfile?.call();
    final retirement = args['is_retirement'];
    final result = <String, Object?>{
      'status': 'ok',
      'as_of': ctx.asOf,
      ...GoalProjectionBuilder.build(
        currentPortfolioValue: ctx.summary?.totalValue ?? 0,
        targetAmount: _positive(ToolArgs.number(args, 'target_amount')),
        targetDate: ToolArgs.date(args, 'target_date'),
        label: ToolArgs.string(args, 'goal_label'),
        monthlyContribution: _nonNegative(monthly),
        currentSavings: _nonNegative(ToolArgs.number(args, 'current_savings')),
        desiredMonthlyIncome: _positive(
          ToolArgs.number(args, 'desired_monthly_income'),
        ),
        isRetirement: retirement is bool ? retirement : null,
        isPurchase:
            ToolArgs.string(args, 'goal_type') ==
            GoalProjectionBuilder.goalPurchase,
        incomeStrategy: IncomeStrategy.fromKey(
          ToolArgs.string(args, 'income_strategy'),
        ),
        dividendYield: ctx.data.plans.dividendYield,
        statedRisk: RiskTolerance.fromStorage(ToolArgs.string(args, 'risk')),
        profile: profile,
        savedGoal: saved,
        asOf: ctx.now,
      ),
      'investor_profile': InvestorProfileContext.build(profile, ctx.now),
    };
    final planId = result[GoalProjectionBuilder.planIdKey];
    if (planId is String) ctx.data.plans.record(planId, result);
    return result;
  }

  static double? _positive(double? v) => v != null && v > 0 ? v : null;
  static double? _nonNegative(double? v) => v != null && v >= 0 ? v : null;
}

/// Guarda la meta (Premium). Solo cuando el usuario lo pide explícitamente.
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
    if (!ctx.allows(PlanFeature.goals)) {
      return ctx.lockedFeature(PlanFeature.goals);
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

/// La compra mensual de un plan: qué comprar cada mes y cuánto a cada uno,
/// con el rendimiento real de cada instrumento (Premium, como las metas).
class GetMonthlyBuyPlanTool implements DataTool {
  GetMonthlyBuyPlanTool(this.ctx);

  final AssistantToolContext ctx;

  static const toolName = 'get_monthly_buy_plan';

  @override
  String get name => toolName;

  @override
  String get description =>
      'Turns a savings plan from get_goal_projection into a MONTHLY BUY PLAN: '
      'you pick 2-6 instruments, each for an asset class of the plan\'s '
      'suggested_allocation; the app splits the monthly savings among them '
      '(ETFs as the base, at most 15% per individual stock), fetches their '
      'real dividend yields and recomputes the plan with the weighted yield. '
      'For a plan that lives off dividends, equities = 2 dividend-focused '
      'ETFs + 1-2 dividend stocks (it returns needs_retry otherwise). '
      'Use it ONLY for a savings/retirement plan, when the user asks what '
      'to buy each month or which stocks/ETFs to use for it ("armá mi '
      'compra mensual", "¿en qué invierto cada mes?"). NOT for registering '
      'an operation the user already did ("compré 10 AAPL" → propose_buy). '
      'Never compute the amounts yourself.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'plan_id': {
        'type': 'string',
        'description': 'plan_id of the plan (default: the latest one).',
      },
      'instruments': {
        'type': 'array',
        'minItems': 2,
        'maxItems': 6,
        'items': {
          'type': 'object',
          'properties': {
            'ticker': {'type': 'string'},
            'asset_class': {
              'type': 'string',
              'enum': ['equities', 'bonds', 'cash'],
            },
          },
          'required': ['ticker', 'asset_class'],
          'additionalProperties': false,
        },
      },
    },
    'required': ['instruments'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    if (!ctx.allows(PlanFeature.goals)) {
      return ctx.lockedFeature(PlanFeature.goals);
    }
    final base = ctx.data.plans.lookup(ToolArgs.string(args, 'plan_id'));
    if (base == null) {
      return {
        'status': 'needs_plan',
        'reason': 'Call get_goal_projection first: there is no plan yet.',
      };
    }
    final picks = <BuyPlanPick>[];
    final raw = args['instruments'];
    for (final item in raw is List ? raw : const []) {
      if (item is! Map) continue;
      final tickers = ToolArgs.tickers({
        'tickers': [item['ticker']],
      });
      final cls = PlanAssetClass.values.where(
        (c) => c.key == item['asset_class'],
      );
      if (tickers.isEmpty || cls.isEmpty) continue;
      picks.add(BuyPlanPick(tickers.first, cls.first));
      if (picks.length == 6) break;
    }
    if (picks.length < 2) return ToolArgs.invalid();

    final fetched = await ctx.data.dividends.fetch([
      for (final p in picks) p.ticker,
    ]);
    final result = BuyPlanBuilder.build(
      base: base,
      picks: picks,
      info: (fetched['tickers'] as Map?)?.cast<String, Object?>() ?? const {},
    );
    if (result['status'] != 'ok') return result;

    // Los planes siguientes usan el rendimiento real de esta compra.
    final yieldPct = result['weighted_dividend_yield_pct'];
    if (yieldPct is num) ctx.data.plans.dividendYield = yieldPct / 100;
    final planId = result[GoalProjectionBuilder.planIdKey];
    final stored = {...result, 'investor_profile': base['investor_profile']};
    if (planId is String) ctx.data.plans.record(planId, stored);
    return {...stored, 'as_of': ctx.asOf};
  }
}
