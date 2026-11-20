import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/turn_activity.dart';

/// El análisis Gold de cortesía de la semana (Free y Premium).
///
/// Cuándo se usa: cuando el modelo pide, en UNA ronda, las tres fuentes de
/// Gold del análisis (fundamentals, earnings y noticias) para un mismo y
/// único ticker. Esa combinación solo aparece en un análisis
/// (`[W:ANALYSIS]`) — se decide por lo que el modelo va a pedir, no por
/// palabras de la pregunta — y así una pregunta suelta de noticias no gasta
/// ni abre la cortesía.
///
/// Se gasta en el servidor ANTES de ejecutar las tools ([consume], atómico):
/// si la ronda la usa, los datos se sirven; si el servidor dice que ya se
/// usó, las fuentes quedan `locked` como siempre.
///
/// Free: solo para tickers propios (la cortesía abre Gold, no el mercado de
/// Premium). Premium: cualquier ticker.
class WeeklyFreeAnalysisGrant {
  WeeklyFreeAnalysisGrant({
    required this.ctx,
    required this.available,
    required this.consume,
  });

  final AssistantToolContext ctx;

  /// Lo que la app sabe de la semana (del servidor, al abrir el chat). Si
  /// es `false`, ni se intenta: evita un viaje al servidor por ronda.
  final bool available;

  /// Gasta la cortesía para [ticker] en el servidor.
  final Future<bool> Function(String ticker) consume;

  static const goldSources = {'get_fundamentals', 'get_earnings', 'get_news'};

  bool _decided = false;

  /// `true` si este turno usó la cortesía (para refrescar el estado).
  bool get used => ctx.courtesyTicker != null;

  Future<void> beforeRound(List<PendingToolCall> calls) async {
    if (_decided || !available || ctx.allowsAnyGoldData) return;
    final ticker = analysisTicker(calls);
    if (ticker == null) return;
    if (ctx.tier == SubscriptionTier.free && !ctx.heldTickers.contains(ticker)) {
      return;
    }
    _decided = true;
    if (await consume(ticker)) ctx.courtesyTicker = ticker;
  }

  /// El ticker si [calls] pide las 3 fuentes de Gold para uno solo.
  static String? analysisTicker(List<PendingToolCall> calls) {
    final tickersBySource = <String, Set<String>>{};
    for (final call in calls) {
      if (!goldSources.contains(call.name)) continue;
      final tickers = {
        for (final t in (call.args['tickers'] as List? ?? const []))
          '$t'.toUpperCase(),
      };
      tickersBySource.putIfAbsent(call.name, () => {}).addAll(tickers);
    }
    if (tickersBySource.length != goldSources.length) return null;
    final all = tickersBySource.values.expand((t) => t).toSet();
    if (all.length != 1) return null;
    final ticker = all.single;
    return tickersBySource.values.every((t) => t.contains(ticker))
        ? ticker
        : null;
  }
}
