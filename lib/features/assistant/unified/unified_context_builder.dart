import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_context_builder.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_earnings_enricher.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_news_enricher.dart';
import 'package:portfolio_assistant/features/assistant/unified/message_needs.dart';
import 'package:portfolio_assistant/features/assistant/utils/portfolio_context_builder.dart';
import 'package:portfolio_assistant/features/assistant/utils/position_periods_builder.dart';

/// Arma el ASSISTANT_SNAPSHOT del pipeline unificado. Cada pieza se pide
/// SOLO si [MessageNeeds] dice que el mensaje la necesita:
///
/// - `portfolio`: siempre (es local, no cuesta ningún pedido externo).
///   `position_periods` solo para las tenencias mencionadas, o para todas
///   si la pregunta es un superlativo/período sobre la propia cartera.
/// - `tickers`: solo los tickers del mensaje (o el de seguimiento). Una
///   pregunta conceptual o sin ticker no pide ningún precio.
/// - earnings / noticias: solo si hay tickers, y según el plan.
///
/// El gating por plan ya se evaluó antes ([UnifiedAccessPolicy]); acá
/// [marketDataAllowed]/[newsAllowed] solo deciden qué se pide y qué se
/// marca como `locked`.
abstract final class UnifiedContextBuilder {
  static Future<Map<String, Object?>> build({
    required MessageNeeds needs,
    required String userMessage,
    required QuoteRepository quoteRepository,
    required bool marketDataAllowed,
    required bool newsAllowed,
    PortfolioSummary? summary,
    List<PortfolioHistoryPoint> history = const [],
    List<ClosedPosition> closedPositions = const [],
    ExploreNewsEnricher? newsEnricher,
    ExploreEarningsEnricher? earningsEnricher,
    DateTime? asOf,
  }) async {
    final hasOpen = summary != null && summary.valuations.isNotEmpty;

    final periodTickers =
        needs.needsAllPositionPeriods ? null : needs.heldTickers;
    final positionPeriods =
        hasOpen && (periodTickers == null || periodTickers.isNotEmpty)
            ? await PositionPeriodsBuilder.build(
              summary: summary,
              quoteRepository: quoteRepository,
              onlyTickers: periodTickers,
            )
            : const <String, Map<String, Object?>>{};

    final portfolio = PortfolioContextBuilder.buildMap(
      summary,
      history: history,
      positionPeriods: positionPeriods,
      closedPositions: closedPositions,
      asOf: asOf,
    )..remove('as_of');

    final weights = {
      for (final p in (portfolio['positions'] as List? ?? const []))
        (p as Map)['ticker'] as String: p['weight_pct'],
    };

    final tickers = <String, Object?>{};
    for (final ticker in needs.tickers) {
      final held = needs.heldTickers.contains(ticker);
      // Defensa: el gating ya cortó antes si faltaba el plan; si igual
      // llega un ticker externo sin acceso, no se pide su precio.
      if (!held && !marketDataAllowed) continue;
      final entry = await ExploreContextBuilder.buildTickerEntry(
        ticker: ticker,
        quoteRepository: quoteRepository,
      );
      tickers[ticker] = {
        'held': held,
        ...entry,
        if (held && weights[ticker] != null) 'weight_pct': weights[ticker],
      };
    }

    var snapshot = <String, Object?>{
      'as_of': (asOf ?? DateTime.now()).toUtc().toIso8601String(),
      'data_source': 'yahoo_finance',
      'access': {'market_data': marketDataAllowed, 'news': newsAllowed},
      'portfolio': portfolio,
      'tickers': tickers,
    };

    final proxy = needs.marketProxyTicker;
    if (proxy != null && tickers.containsKey(proxy)) {
      snapshot['market_proxy_ticker'] = proxy;
      snapshot['market_proxy_label'] =
          'S&P 500 (ETF SPY como referencia del mercado estadounidense)';
    }

    if (needs.ambiguousCandidate != null) {
      snapshot['ticker_ambiguous'] = {
        'candidate': needs.ambiguousCandidate,
        'matches': [
          for (final m in needs.ambiguousMatches ?? const [])
            {'symbol': m.symbol, 'description': m.description},
        ],
      };
    }

    if (tickers.isNotEmpty) {
      snapshot = {
        ...snapshot,
        ...await _earnings(tickers, newsAllowed, earningsEnricher),
        ...await _news(tickers, needs, userMessage, newsAllowed, newsEnricher),
      };
    }

    return snapshot;
  }

  // Los enrichers leen `explore_tickers` del snapshot que reciben: se les
  // pasa una vista con esa clave y se copian solo sus campos de salida, así
  // el snapshot unificado no arrastra el nombre del modo viejo.

  static Future<Map<String, Object?>> _earnings(
    Map<String, Object?> tickers,
    bool allowed,
    ExploreEarningsEnricher? enricher,
  ) async {
    if (!allowed) {
      return {
        'earnings_calendar': <String, Object?>{},
        'earnings_calendar_status': 'locked',
      };
    }
    if (enricher == null) return const {};
    final enriched = await enricher.enrich(
      snapshot: {'explore_tickers': tickers},
    );
    return {
      if (enriched.containsKey('earnings_calendar'))
        'earnings_calendar': enriched['earnings_calendar'],
      if (enriched.containsKey('earnings_calendar_status'))
        'earnings_calendar_status': enriched['earnings_calendar_status'],
    };
  }

  static Future<Map<String, Object?>> _news(
    Map<String, Object?> tickers,
    MessageNeeds needs,
    String userMessage,
    bool allowed,
    ExploreNewsEnricher? enricher,
  ) async {
    if (!allowed) {
      return needs.isNewsQuery
          ? {'news_sources': <Object?>[], 'news_enrichment': 'locked'}
          : const {};
    }
    if (enricher == null) return const {};
    final enriched = await enricher.enrich(
      snapshot: {'explore_tickers': tickers},
      userMessage: userMessage,
    );
    return {
      'news_sources': enriched['news_sources'],
      'news_enrichment': enriched['news_enrichment'],
    };
  }
}
