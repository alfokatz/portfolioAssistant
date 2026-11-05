import 'package:portfolio_assistant/features/assistant/data/market_taste/market_taste_repository.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/tool_args.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/turn_activity.dart';

/// La consulta de mercado gratis del mes (Free, spec 2026-11-03).
///
/// Cuándo se usa: cuando una ronda pide precio, holdings de un ETF o
/// dividendos de al menos un ticker que el usuario no tiene y su plan no
/// incluye datos de mercado. Una sola decisión por turno: lo que se gasta
/// cubre el turno entero (todas sus rondas y tickers).
///
/// Se gasta en el servidor ANTES de ejecutar las tools ([consume], atómico e
/// idempotente por turno). Con `granted`, esas tools sirven datos
/// (`AssistantToolContext.marketDataServed`); con `exhausted`, el turno no se
/// corta: responde sin números del ticker ajeno (ver `AssistantTurnPolicy`).
/// Cualquier otra cosa deja el comportamiento de siempre.
///
/// No abre watchlist ni las fuentes de Gold: solo estas tres tools.
class MarketTasteGrant {
  MarketTasteGrant({
    required this.ctx,
    required this.available,
    required this.turnId,
    required this.consume,
  });

  final AssistantToolContext ctx;

  /// Lo que la app sabe del servidor (`market_taste_status`, al abrir el
  /// chat). Si es `false`, ni se intenta: Premium/Gold y el interruptor
  /// apagado no hacen viajes al servidor.
  final bool available;

  /// El id del turno en curso (el mismo que viaja en `x-porty-turn-id`).
  final String? Function() turnId;

  final Future<MarketTasteConsume> Function(String turnId, List<String> tickers)
  consume;

  static const marketTools = {'get_quote', 'get_etf_holdings', 'get_dividends'};

  /// El servidor admite de 1 a 6 tickers.
  static const maxTickers = 6;

  bool _decided = false;

  Future<void> beforeRound(List<PendingToolCall> calls) async {
    if (_decided || !available || ctx.marketDataAllowed) return;
    final others = foreignTickers(calls, ctx.heldTickers);
    if (others.isEmpty) return;
    final id = turnId();
    if (id == null) return;
    _decided = true;
    final result = await consume(id, others);
    switch (result.outcome) {
      case MarketTasteOutcome.granted:
        ctx
          ..marketTaste = true
          ..marketTasteRemaining = result.remaining;
      case MarketTasteOutcome.exhausted:
        ctx.marketTasteExhausted = true;
      case MarketTasteOutcome.unavailable:
        break;
    }
  }

  /// Tickers de [calls] que piden las tools de mercado y no están en
  /// [held], en orden y sin repetir.
  static List<String> foreignTickers(
    List<PendingToolCall> calls,
    Set<String> held,
  ) {
    final out = <String>[];
    for (final call in calls) {
      if (!marketTools.contains(call.name)) continue;
      for (final t in ToolArgs.tickers(call.args, max: maxTickers)) {
        if (!held.contains(t) && !out.contains(t)) out.add(t);
      }
    }
    return out.take(maxTickers).toList();
  }
}
