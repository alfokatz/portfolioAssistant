import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_currency.dart';
import 'package:portfolio_assistant/features/assistant/models/manage_action.dart';
import 'package:portfolio_assistant/features/assistant/tools/action_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/advice_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/answer_guide.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/tool_args.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:uuid/uuid.dart';

/// Gestionar desde el chat lo que el usuario ya tiene armado en la app
/// (quitar, pausar, borrar, prender o apagar avisos). Igual que las demás
/// acciones de Porty: la tool solo PROPONE ([ManageOp] en una card
/// `QaActionProposal`); escribe la app cuando el usuario confirma (ver
/// `AssistantProvider._manage`).
abstract final class ManageTools {
  static const proposeWatchlistChange = 'propose_watchlist_change';
  static const proposeAlertChange = 'propose_alert_change';
  static const proposeGoalChange = 'propose_goal_change';
  static const proposeAllocationPlan = 'propose_allocation_plan';
  static const getAppSettings = 'get_app_settings';
  static const proposeSettingsChange = 'propose_settings_change';
  static const proposeMemoryClear = 'propose_memory_clear';
  static const proposeBrokerAction = 'propose_broker_action';

  /// Las que preparan una card (no `get_app_settings`, que solo lee).
  /// Lista y memoria se proponen desde `propose_watch` y
  /// `propose_settings_change` (una tool menos en cada pedido).
  static const names = {
    proposeAlertChange,
    proposeGoalChange,
    proposeAllocationPlan,
    proposeSettingsChange,
    proposeBrokerAction,
  };

  static List<DataTool> build(AssistantToolContext ctx) => [
    ProposeAlertChangeTool(ctx),
    ProposeGoalChangeTool(ctx),
    ProposeAllocationPlanTool(ctx),
    GetAppSettingsTool(ctx),
    ProposeSettingsChangeTool(ctx),
    ProposeBrokerActionTool(ctx),
  ];

  /// La propuesta `ok` (con su guía) para [op] sobre [ticker].
  static Map<String, Object?> propose(
    AssistantToolContext ctx,
    ManageOp op, {
    String ticker = '',
    String? targetId,
    String? targetLabel,
    Map<String, Object?> params = const {},
  }) => ActionGuides.attachTo({
    ...ActionProposal(
      id: const Uuid().v4(),
      kind: ActionKind.manage,
      ticker: ticker,
      manageOp: op,
      targetId: targetId,
      targetLabel: targetLabel,
      params: params,
    ).toToolResult(),
    'as_of': ctx.asOf,
  });
}

/// Cómo responder con cada resultado que no es una propuesta.
abstract final class ManageGuides {
  static const notOnWatchlist =
      'QaAnswerText: it is not on their watchlist (items lists what is); '
      'offer to follow it.';
  static const noChange =
      'QaAnswerText: it is already like that (state says how); nothing to '
      'change.';
  static const alertNotFound =
      'QaAnswerText: no alert matches; list what they have (alerts) in one '
      'line each, if any.';
  static const goalUnknown =
      'QaAnswerText: no saved goal with that id; use an id from saved_goals '
      'or ask which goal.';
  static const notHeld =
      'QaAnswerText: those tickers aren\'t in their portfolio (not_held); '
      'only holdings can count for a goal.';
  static const allocationSum =
      'QaAnswerText only: their targets add up to `sum`%, not 100. Ask in '
      'ONE short question how to adjust (or offer to scale them '
      'proportionally). Never decide for them.';
  static const allocationNoPlan =
      'QaAnswerText: they have no portfolio plan yet; ask how much they want '
      'of each investment.';
  static const settings =
      'One fact asked → QaAnswerText only. Several → QaAnswerText (one '
      'sentence) + QaInfoList, one row per item (a toggle: value '
      '"Prendido"/"Apagado"). Plain words.';
  static const noMemory = 'QaAnswerText: you have nothing saved about them.';
  static const brokerNotConnected =
      'QaAnswerText: that account isn\'t connected (accounts says how each '
      'is); connecting is done in Ajustes → Cuentas conectadas (never ask '
      'for keys or passwords in the chat).';
  static const brokerReconnect =
      'QaAnswerText: the broker closed the access; they reconnect it in '
      'Ajustes → Cuentas conectadas. You can\'t do it from the chat.';
  static const alertAmbiguous =
      'QaAnswerText only: they have several alerts for that ticker '
      '(candidates); ask which one in ONE short question, one "• " line per '
      'candidate.';
}

class ProposeWatchlistChangeTool implements DataTool {
  ProposeWatchlistChangeTool(this.ctx);

  final AssistantToolContext ctx;

  static const _changes = {
    'remove': ManageOp.unwatch,
    'alerts_on': ManageOp.watchNotifyOn,
    'alerts_off': ManageOp.watchNotifyOff,
  };

  @override
  String get name => ManageTools.proposeWatchlistChange;

  @override
  String get description =>
      'Prepares a change to a ticker on the user\'s WATCHLIST for them to '
      'confirm in a card: remove it ("dejá de seguir AMZN", "sacá Netflix '
      'de mi lista"), or turn its sharp-move alerts on/off ("no me avises '
      'más de NVDA"). Nothing changes until they confirm. status: ok | '
      'not_on_watchlist | no_change | needs_input | locked (Premium) | '
      'failed.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'ticker': {'type': 'string'},
      'change': {
        'type': 'string',
        'enum': ['remove', 'alerts_on', 'alerts_off'],
      },
    },
    'required': ['ticker', 'change'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    if (!ctx.marketDataAllowed) {
      return ctx.lockedFeature(PlanFeature.marketData);
    }
    final raw = ToolArgs.string(args, 'ticker');
    final tickers =
        raw == null
            ? const <String>[]
            : ToolArgs.tickers({
              'tickers': [raw],
            }, max: 1);
    final op = _changes[ToolArgs.string(args, 'change')];
    if (tickers.isEmpty || op == null) {
      return ActionGuides.attachTo({
        'status': 'needs_input',
        'missing': [if (tickers.isEmpty) 'ticker', if (op == null) 'change'],
      });
    }
    final ticker = tickers.first;
    final load = ctx.loadWatchlist;
    if (load == null) return {'status': 'failed', 'reason': 'unavailable'};
    final List<Map<String, Object?>> items;
    try {
      items = await load();
    } catch (_) {
      return {'status': 'failed', 'reason': 'unavailable'};
    }
    final item =
        items
            .where((i) => '${i['ticker'] ?? ''}'.toUpperCase() == ticker)
            .firstOrNull;
    if (item == null) {
      return AnswerGuide.attach({
        'status': 'not_on_watchlist',
        'ticker': ticker,
        'items': [for (final i in items) i['ticker']],
      }, ManageGuides.notOnWatchlist);
    }
    final alertsOn = item['alerts_on'] != false;
    if ((op == ManageOp.watchNotifyOn && alertsOn) ||
        (op == ManageOp.watchNotifyOff && !alertsOn)) {
      return AnswerGuide.attach({
        'status': 'no_change',
        'ticker': ticker,
        'state': alertsOn ? 'alerts_on' : 'alerts_off',
      }, ManageGuides.noChange);
    }
    return ManageTools.propose(ctx, op, ticker: ticker);
  }
}

class ProposeAlertChangeTool implements DataTool {
  ProposeAlertChangeTool(this.ctx);

  final AssistantToolContext ctx;

  static const _changes = {
    'pause': ManageOp.alertPause,
    'resume': ManageOp.alertResume,
    'delete': ManageOp.alertDelete,
  };

  @override
  String get name => ManageTools.proposeAlertChange;

  @override
  String get description =>
      'Card to confirm pausing, resuming or deleting a PRICE ALERT (alert_id '
      'from list_price_alerts, or ticker). status: ok | ambiguous '
      '(candidates) | not_found | no_change.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'alert_id': {'type': 'string'},
      'ticker': {'type': 'string'},
      'change': {
        'type': 'string',
        'enum': ['pause', 'resume', 'delete'],
      },
    },
    'required': ['change'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final op = _changes[ToolArgs.string(args, 'change')];
    final id = ToolArgs.string(args, 'alert_id');
    final ticker = ToolArgs.string(args, 'ticker')?.trim().toUpperCase();
    if (op == null || (id == null && (ticker == null || ticker.isEmpty))) {
      return ActionGuides.attachTo({
        'status': 'needs_input',
        'missing': [
          if (op == null) 'change',
          if (id == null && (ticker == null || ticker.isEmpty)) 'ticker',
        ],
      });
    }
    final load = ctx.loadPriceAlerts;
    if (load == null) return {'status': 'failed', 'reason': 'unavailable'};
    final List<Map<String, Object?>> alerts;
    try {
      alerts = await load();
    } catch (_) {
      return {'status': 'failed', 'reason': 'unavailable'};
    }
    final matches = [
      for (final a in alerts)
        if (id != null
            ? a['id'] == id
            : '${a['symbol'] ?? ''}'.toUpperCase() == ticker)
          a,
    ];
    if (matches.isEmpty) {
      return AnswerGuide.attach({
        'status': 'not_found',
        'alerts': [for (final a in alerts) alertLabel(a)],
      }, ManageGuides.alertNotFound);
    }
    if (matches.length > 1) {
      return AnswerGuide.attach({
        'status': 'ambiguous',
        'candidates': [
          for (final a in matches)
            {'alert_id': a['id'], 'alert': alertLabel(a)},
        ],
      }, ManageGuides.alertAmbiguous);
    }
    final alert = matches.single;
    final status = alert['status'];
    if ((op == ManageOp.alertPause && status == 'paused') ||
        (op == ManageOp.alertResume && status == 'active')) {
      return AnswerGuide.attach({
        'status': 'no_change',
        'state': status,
      }, ManageGuides.noChange);
    }
    return ManageTools.propose(
      ctx,
      op,
      ticker: '${alert['symbol'] ?? ''}'.toUpperCase(),
      targetId: '${alert['id']}',
      targetLabel: alertLabel(alert),
    );
  }

  /// "VOO sube a $750,00", "NVDA baja 10%": cómo se nombra una alerta en la
  /// card y en la respuesta.
  static String alertLabel(Map<String, Object?> alert) {
    final symbol = '${alert['symbol'] ?? ''}'.toUpperCase();
    final target = alert['target'];
    final t = target is num ? target.toDouble() : 0.0;
    return switch (alert['condition']) {
      'below' => '$symbol baja a ${AppNumberFormat.money(t)}',
      'pct_up' => '$symbol sube ${t.round()}%',
      'pct_down' => '$symbol baja ${t.round()}%',
      _ => '$symbol sube a ${AppNumberFormat.money(t)}',
    };
  }
}

class ProposeGoalChangeTool implements DataTool {
  ProposeGoalChangeTool(this.ctx);

  final AssistantToolContext ctx;

  static const _changes = {
    'delete': ManageOp.goalDelete,
    'mark_achieved': ManageOp.goalAchieved,
    'set_holdings': ManageOp.goalHoldings,
    'set_outside_savings': ManageOp.goalOutsideSavings,
  };

  @override
  String get name => ManageTools.proposeGoalChange;

  @override
  String get description =>
      'Card to confirm a change to a SAVED goal (saved_goals id): delete, '
      'mark_achieved, set_holdings (tickers = full new list of holdings that '
      'count) or set_outside_savings (TOTAL outside the app, holdings never '
      'included). status: ok | invalid | needs_input.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'goal_id': {'type': 'string'},
      'change': {
        'type': 'string',
        'enum': [
          'delete',
          'mark_achieved',
          'set_holdings',
          'set_outside_savings',
        ],
      },
      'tickers': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'outside_savings_usd': {'type': 'number'},
    },
    'required': ['goal_id', 'change'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final op = _changes[ToolArgs.string(args, 'change')];
    final goal = GoalTools.byRef(ctx, ToolArgs.string(args, 'goal_id'));
    if (op == null) {
      return ActionGuides.attachTo({
        'status': 'needs_input',
        'missing': ['change'],
      });
    }
    if (goal == null) {
      return AnswerGuide.attach({
        'status': 'invalid',
        'reason': 'unknown_goal_id',
      }, ManageGuides.goalUnknown);
    }
    final params = <String, Object?>{};
    if (op == ManageOp.goalHoldings) {
      final raw = args['tickers'];
      if (raw is! List) {
        return ActionGuides.attachTo({
          'status': 'needs_input',
          'missing': ['tickers'],
        });
      }
      final tickers = {for (final t in raw) '$t'.trim().toUpperCase()}
        ..removeWhere((t) => t.isEmpty);
      final notHeld = tickers.difference(ctx.heldTickers);
      if (notHeld.isNotEmpty) {
        return AnswerGuide.attach({
          'status': 'invalid',
          'reason': 'not_held',
          'not_held': notHeld.toList(),
        }, ManageGuides.notHeld);
      }
      params['tickers'] = tickers.toList()..sort();
    } else if (op == ManageOp.goalOutsideSavings) {
      final amount = ToolArgs.number(args, 'outside_savings_usd');
      if (amount == null) {
        return ActionGuides.attachTo({
          'status': 'needs_input',
          'missing': ['outside_savings_usd'],
        });
      }
      if (amount < 0 || amount >= 1e8) return ToolArgs.invalid();
      params['amount'] = amount;
    }
    return ActionGuides.attachTo({
      ...ActionProposal(
        id: const Uuid().v4(),
        kind: ActionKind.manage,
        ticker: '',
        manageOp: op,
        targetId: goal.id,
        targetLabel: goal.label,
        params: params,
      ).toToolResult(),
      'as_of': ctx.asOf,
    });
  }
}

class ProposeAllocationPlanTool implements DataTool {
  ProposeAllocationPlanTool(this.ctx);

  final AssistantToolContext ctx;

  static final _ticker = RegExp(r'^[A-Z0-9.\-^=]{1,15}$');

  @override
  String get name => ManageTools.proposeAllocationPlan;

  @override
  String get description =>
      'Card to confirm the user\'s PORTFOLIO PLAN: targets = THEIR full plan '
      '(% per ticker, sum 100; never choose them), or omit targets to change '
      'only its alerts. status: ok | invalid (sum, no_plan) | locked.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'targets': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'ticker': {'type': 'string'},
            'pct': {'type': 'number'},
          },
          'required': ['ticker', 'pct'],
          'additionalProperties': false,
        },
      },
      'drift_threshold': {'type': 'number'},
      'alerts': {
        'type': 'string',
        'enum': ['on', 'off'],
      },
      'frequency': {
        'type': 'string',
        'enum': ['weekly', 'monthly'],
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    if (!ctx.allows(PlanFeature.allocationPlan)) {
      return ctx.lockedFeature(PlanFeature.allocationPlan);
    }
    final params = <String, Object?>{};
    final raw = args['targets'];
    if (raw is List && raw.isNotEmpty) {
      final targets = <String, double>{};
      for (final item in raw) {
        if (item is! Map) continue;
        final ticker = '${item['ticker'] ?? ''}'.trim().toUpperCase();
        final pct = item['pct'];
        if (!_ticker.hasMatch(ticker) || pct is! num || pct <= 0) {
          return ToolArgs.invalid();
        }
        targets[ticker] = (targets[ticker] ?? 0) + pct.toDouble();
      }
      final sum = targets.values.fold(0.0, (a, b) => a + b);
      if ((sum - 100).abs() > 0.5) {
        return AnswerGuide.attach({
          'status': 'invalid',
          'reason': 'sum',
          'sum': (sum * 10).roundToDouble() / 10,
        }, ManageGuides.allocationSum);
      }
      params['targets'] = targets;
    }
    final threshold = ToolArgs.number(args, 'drift_threshold');
    if (threshold != null) {
      if (threshold < 1 || threshold > 50) return ToolArgs.invalid();
      params['threshold'] = threshold.roundToDouble();
    }
    final alerts = ToolArgs.string(args, 'alerts');
    if (alerts != null) params['notify'] = alerts == 'on';
    final frequency = ToolArgs.string(args, 'frequency');
    if (frequency == 'weekly' || frequency == 'monthly') {
      params['frequency'] = frequency;
    }
    if (params.isEmpty) {
      return ActionGuides.attachTo({
        'status': 'needs_input',
        'missing': ['targets'],
      });
    }
    if (!params.containsKey('targets')) {
      final load = ctx.loadAllocationPlan;
      final plan = load == null ? null : await load().catchError((_) => null);
      if (plan == null || plan.isEmpty) {
        return AnswerGuide.attach({
          'status': 'invalid',
          'reason': 'no_plan',
        }, ManageGuides.allocationNoPlan);
      }
    }
    return ManageTools.propose(
      ctx,
      ManageOp.allocationSave,
      targetLabel: 'Tu plan de cartera',
      params: params,
    );
  }
}

/// Los valores que acepta cada ajuste (lo demás se descarta).
final _settingValues = <String, bool Function(Object?)>{
  for (final k in AppSettingKeys.toggles) k: (v) => v is bool,
  AppSettingKeys.sensitivity:
      (v) => const {'low', 'normal', 'high'}.contains(v),
  AppSettingKeys.quietHours:
      (v) =>
          v == 'off' ||
          (v is String &&
              RegExp(
                r'^([01]?\d|2[0-3]):[0-5]\d-([01]?\d|2[0-3]):[0-5]\d$',
              ).hasMatch(v)),
  AppSettingKeys.currency:
      (v) =>
          v is String &&
          DisplayCurrency.values.any((c) => c.code == v.toUpperCase()),
  AppSettingKeys.theme: (v) => const {'system', 'light', 'dark'}.contains(v),
  AppSettingKeys.language: (v) => v == 'es' || v == 'en',
};

class GetAppSettingsTool implements DataTool {
  GetAppSettingsTool(this.ctx);

  final AssistantToolContext ctx;

  @override
  String get name => ManageTools.getAppSettings;

  @override
  String get description =>
      'Their account (plan, queries, connected accounts, achieved goals) and '
      'app settings.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {},
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final load = ctx.loadAppSettings;
    if (load == null) return {'status': 'failed', 'reason': 'unavailable'};
    try {
      final account = ctx.loadAccountOverview;
      final results = await Future.wait([
        load(),
        if (account != null) account(),
      ]);
      return AnswerGuide.attach({
        'status': 'ok',
        'settings': results.first,
        if (results.length > 1) 'account': results[1],
      }, ManageGuides.settings);
    } catch (_) {
      return {'status': 'failed', 'reason': 'unavailable'};
    }
  }
}

class ProposeSettingsChangeTool implements DataTool {
  ProposeSettingsChangeTool(this.ctx);

  final AssistantToolContext ctx;

  @override
  String get name => ManageTools.proposeSettingsChange;

  @override
  String get description =>
      'Card to confirm APP SETTINGS changes; pass only what changes. '
      'notify_*: booleans (notifications = all of them). '
      'big_move_sensitivity: low = only very big moves. quiet_hours: '
      '"HH:MM-HH:MM" or "off". currency: ISO (USD UYU ARS BRL MXN CLP COP '
      'PEN EUR GBP). forget_everything: delete all you remember about them. '
      'status: ok | no_change.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      AppSettingKeys.notifications: {'type': 'boolean'},
      AppSettingKeys.priceAlerts: {'type': 'boolean'},
      AppSettingKeys.bigMoves: {'type': 'boolean'},
      AppSettingKeys.portfolioMoves: {'type': 'boolean'},
      AppSettingKeys.weeklyReport: {'type': 'boolean'},
      AppSettingKeys.earnings: {'type': 'boolean'},
      AppSettingKeys.showAmounts: {'type': 'boolean'},
      AppSettingKeys.sensitivity: {
        'type': 'string',
        'enum': ['low', 'normal', 'high'],
      },
      AppSettingKeys.quietHours: {'type': 'string'},
      AppSettingKeys.currency: {'type': 'string'},
      AppSettingKeys.theme: {
        'type': 'string',
        'enum': ['system', 'light', 'dark'],
      },
      AppSettingKeys.haptics: {'type': 'boolean'},
      AppSettingKeys.language: {
        'type': 'string',
        'enum': ['es', 'en'],
      },
      'forget_everything': {'type': 'boolean'},
    },
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    if (args['forget_everything'] == true) {
      return ProposeMemoryClearTool(ctx).run(const {});
    }
    final changes = <String, Object?>{};
    for (final e in args.entries) {
      final valid = _settingValues[e.key];
      if (valid == null) continue;
      if (!valid(e.value)) return ToolArgs.invalid();
      changes[e.key] =
          e.key == AppSettingKeys.currency
              ? '${e.value}'.toUpperCase()
              : e.value;
    }
    if (changes.isEmpty) {
      return ActionGuides.attachTo({
        'status': 'needs_input',
        'missing': ['what_to_change'],
      });
    }
    final load = ctx.loadAppSettings;
    if (load != null) {
      try {
        final current = await load();
        changes.removeWhere((k, v) => current[k] == v);
      } catch (_) {}
      if (changes.isEmpty) {
        return AnswerGuide.attach({
          'status': 'no_change',
        }, ManageGuides.noChange);
      }
    }
    return ManageTools.propose(
      ctx,
      ManageOp.settingsChange,
      targetLabel: 'Tus ajustes',
      params: {'changes': changes},
    );
  }
}

class ProposeMemoryClearTool implements DataTool {
  ProposeMemoryClearTool(this.ctx);

  final AssistantToolContext ctx;

  @override
  String get name => ManageTools.proposeMemoryClear;

  @override
  String get description =>
      'Prepares deleting EVERYTHING you remember about the user ("olvidate '
      'de todo lo que sabés de mí"), for them to confirm in a card. To '
      'forget one fact use forget_about_user instead. status: ok | empty.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {},
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    if (ctx.userMemories.isEmpty) {
      return AnswerGuide.attach({'status': 'empty'}, ManageGuides.noMemory);
    }
    return ManageTools.propose(
      ctx,
      ManageOp.memoryClear,
      targetLabel: 'Lo que sé de vos',
    );
  }
}

class ProposeBrokerActionTool implements DataTool {
  ProposeBrokerActionTool(this.ctx);

  final AssistantToolContext ctx;

  @override
  String get name => ManageTools.proposeBrokerAction;

  @override
  String get description =>
      'Card to confirm syncing or disconnecting a connected eToro/Binance '
      'account (disconnect: ask keep_positions if unsaid). Connecting is only '
      'in the app. status: ok | not_connected | reconnect_required | locked.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'broker': {
        'type': 'string',
        'enum': ['etoro', 'binance'],
      },
      'action': {
        'type': 'string',
        'enum': ['sync', 'disconnect'],
      },
      'keep_positions': {'type': 'boolean'},
    },
    'required': ['broker', 'action'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    if (!ctx.allows(PlanFeature.brokerSync)) {
      return ctx.lockedFeature(PlanFeature.brokerSync);
    }
    final broker = ToolArgs.string(args, 'broker');
    final action = ToolArgs.string(args, 'action');
    final keep = args['keep_positions'];
    final missing = [
      if (broker != 'etoro' && broker != 'binance') 'broker',
      if (action != 'sync' && action != 'disconnect') 'action',
      if (action == 'disconnect' && keep is! bool) 'keep_positions',
    ];
    if (missing.isNotEmpty) {
      return ActionGuides.attachTo({
        'status': 'needs_input',
        'missing': missing,
      });
    }
    final load = ctx.loadConnectedAccounts;
    if (load == null) return {'status': 'failed', 'reason': 'unavailable'};
    final Map<String, String> accounts;
    try {
      accounts = await load();
    } catch (_) {
      return {'status': 'failed', 'reason': 'unavailable'};
    }
    final status = accounts[broker];
    if (status == 'not_connected' || status == null) {
      return AnswerGuide.attach({
        'status': 'not_connected',
        'accounts': accounts,
      }, ManageGuides.brokerNotConnected);
    }
    if (status == 'reconnect_required' && action == 'sync') {
      return AnswerGuide.attach({
        'status': 'reconnect_required',
      }, ManageGuides.brokerReconnect);
    }
    return ManageTools.propose(
      ctx,
      action == 'sync' ? ManageOp.brokerSync : ManageOp.brokerDisconnect,
      targetLabel: broker == 'binance' ? 'Binance' : 'eToro',
      params: {'broker': broker, if (action == 'disconnect') 'keep': keep},
    );
  }
}
