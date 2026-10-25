import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/tool_args.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:uuid/uuid.dart';

/// Alertas de precio desde el chat (F5 del plan de notificaciones push).
/// Igual que [ActionTools]: `propose_price_alert` NO crea nada, devuelve un
/// [ActionProposal] (`kind: alert`) que la card `QaActionProposal` muestra,
/// y la alerta se crea recién cuando el usuario confirma.
///
/// Sin gating por plan: Free tiene 1 alerta. El tope lo controla la base al
/// confirmar (`alert_limit_reached` → paywall).
abstract final class AlertTools {
  static const proposePriceAlert = 'propose_price_alert';
  static const listPriceAlerts = 'list_price_alerts';

  static const names = {proposePriceAlert, listPriceAlerts};

  static List<DataTool> build(AssistantToolContext ctx) => [
    ProposePriceAlertTool(ctx),
    ListPriceAlertsTool(ctx),
  ];
}

const _uuid = Uuid();

class ProposePriceAlertTool implements DataTool {
  ProposePriceAlertTool(this.ctx);

  final AssistantToolContext ctx;

  static const _conditions = {'above', 'below', 'pct_up', 'pct_down'};

  @override
  String get name => AlertTools.proposePriceAlert;

  @override
  String get description =>
      'Prepares a PRICE ALERT ("avisame si VOO pasa 750", "avisame si NVDA '
      'baja 10%") for the user to review and confirm in a card. Nothing is '
      'created until they confirm; the app then sends a notification when '
      'the price crosses. condition: above / below (target = price in USD) '
      'or pct_up / pct_down (target = percent from today). repeat=true only '
      'if they want it every time it crosses. status: ok (show '
      'QaActionProposal with proposal_id) | needs_input (ask for everything '
      'in missing, in ONE question) | invalid (already_met: the price is '
      'already there, current_price says where; percent_range: 1-90) | '
      'failed (price_unavailable: check the ticker).';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'ticker': {
        'type': 'string',
        'description':
            'US ticker. If the user named a company and the ticker is not '
            'known yet, call search_symbol first.',
      },
      'condition': {
        'type': 'string',
        'enum': ['above', 'below', 'pct_up', 'pct_down'],
      },
      'target': {
        'type': 'number',
        'description':
            'Price in USD (above/below) or percent (pct_up/pct_down), as '
            'the user said it.',
      },
      'repeat': {
        'type': 'boolean',
        'description': 'true if they want it every time, not just once.',
      },
    },
    'required': ['ticker'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final raw = ToolArgs.string(args, 'ticker');
    final tickers =
        raw == null
            ? const <String>[]
            : ToolArgs.tickers({
              'tickers': [raw],
            }, max: 1);
    final ticker = tickers.isEmpty ? null : tickers.first;
    final condition = ToolArgs.string(args, 'condition');
    final target = ToolArgs.number(args, 'target');
    final missing = [
      if (ticker == null) 'ticker',
      if (condition == null || !_conditions.contains(condition) ||
          target == null)
        'target',
    ];
    if (missing.isNotEmpty) {
      return {'status': 'needs_input', 'missing': missing};
    }
    if (target! <= 0) return {'status': 'invalid', 'reason': 'invalid_target'};
    final isPercent = condition!.startsWith('pct_');
    if (isPercent && (target < 1 || target > 90)) {
      return {'status': 'invalid', 'reason': 'percent_range'};
    }

    final quote = await ctx.data.quoteRepository.getCurrentPrice(ticker!);
    final price = quote.fold((_) => null, (p) => p > 0 ? p : null);
    if (price == null) {
      return {'status': 'failed', 'reason': 'price_unavailable'};
    }
    final alreadyMet = switch (condition) {
      'above' => price >= target,
      'below' => price <= target,
      _ => false,
    };
    if (alreadyMet) {
      return {
        'status': 'invalid',
        'reason': 'already_met',
        'current_price': price,
      };
    }

    return ActionProposal(
      id: _uuid.v4(),
      kind: ActionKind.alert,
      ticker: ticker,
      price: price,
      priceSource: PriceSource.closeOnDate,
      alertCondition: condition,
      alertTarget: target,
      alertRepeatDaily: args['repeat'] == true,
    ).toToolResult();
  }
}

class ListPriceAlertsTool implements DataTool {
  ListPriceAlertsTool(this.ctx);

  final AssistantToolContext ctx;

  @override
  String get name => AlertTools.listPriceAlerts;

  @override
  String get description =>
      'The user\'s price alerts ("¿qué alertas tengo?"): symbol, condition, '
      'target, status (active / triggered / paused). Read-only: to change '
      'them, tell the user to go to Ajustes → Alertas de precio.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {},
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final load = ctx.loadPriceAlerts;
    if (load == null) return {'status': 'failed', 'reason': 'unavailable'};
    try {
      final alerts = await load();
      return {
        'status': alerts.isEmpty ? 'empty' : 'ok',
        'alerts': alerts,
        'as_of': ctx.asOf,
      };
    } catch (_) {
      return {'status': 'failed', 'reason': 'unavailable'};
    }
  }
}
