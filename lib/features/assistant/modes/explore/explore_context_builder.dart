import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/utils/ticker_period_utils.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/broad_market_query.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/company_name_candidate_extractor.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/company_ticker_resolver.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_earnings_enricher.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_news_enricher.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/news_query_detector.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/ticker_extractor.dart';

/// Construye el snapshot de contexto para modo explore desde tickers del mensaje.
abstract final class ExploreContextBuilder {
  // Mismos períodos y labels que `PortfolioContextBuilder._buildPeriodReturns`
  // (para consistencia entre modos) — el historial que trae
  // `getHistoricalDaily` ya cubre de sobra estos rangos (Yahoo Finance
  // devuelve todo el histórico disponible del ticker, no solo 30 días), así
  // que agregar quarter/year acá es solo computarlos, sin fetch extra.
  static const _periods = <String, ({String labelEs, Duration duration})>{
    'day': (labelEs: 'último día', duration: Duration(days: 1)),
    'week': (labelEs: 'últimos 7 días', duration: Duration(days: 7)),
    'month': (labelEs: 'últimos 30 días', duration: Duration(days: 30)),
    'quarter': (labelEs: 'últimos 90 días', duration: Duration(days: 90)),
    'year': (labelEs: 'último año', duration: Duration(days: 365)),
  };

  static Future<Map<String, Object?>> build({
    required String userMessage,
    required QuoteRepository quoteRepository,
    PortfolioSummary? summary,
    DateTime? asOf,
    ExploreNewsEnricher? newsEnricher,
    // `true` por defecto: en la mayoría de las llamadas (tests, y cualquier
    // caller que no pasa un enricher porque no le interesa esta parte del
    // snapshot) la ausencia de enricher simplemente significa "no se
    // chequeó nada" — nunca se agrega ningún campo `news_enrichment`. Solo
    // cuando el caller SABE que el usuario no tiene acceso por su plan
    // (ver `SubscriptionPolicy.isNewsAllowed` en assistant_provider.dart)
    // debe pasar `false` acá, para que una pregunta de noticias real
    // reciba `news_enrichment: 'locked'` en vez de quedar en silencio.
    bool newsAllowed = true,
    ExploreEarningsEnricher? earningsEnricher,
    bool earningsAllowed = true,
    // Último ticker de un turno explore previo en la misma sesión (ver
    // `AssistantProvider._lastExploreTicker`) — resuelve follow-ups que no
    // repiten el ticker ("¿y qué expectativas hay sobre estos resultados?").
    // Es el último recurso: un ticker explícito o resuelto por nombre en
    // ESTE mensaje siempre gana.
    String? fallbackTicker,
    // `null` por defecto en la mayoría de las llamadas (tests, o cualquier
    // caller que no le interesa esta resolución) — sin resolver, ningún
    // nombre de compañía se intenta resolver, simplemente no hay ticker.
    CompanyTickerResolver? tickerResolver,
  }) async {
    final timestamp = (asOf ?? DateTime.now()).toUtc().toIso8601String();
    var tickers = TickerExtractor.extractTickers(userMessage);
    String? marketProxyTicker;
    Map<String, Object?>? tickerAmbiguity;

    if (tickers.isEmpty && isBroadMarketQuery(userMessage)) {
      tickers = [broadMarketProxyTicker];
      marketProxyTicker = broadMarketProxyTicker;
    }

    if (tickers.isEmpty && tickerResolver != null) {
      final candidate = CompanyNameCandidateExtractor.extract(userMessage);
      if (candidate != null) {
        final resolution = await tickerResolver.resolve(candidate);
        if (resolution.ticker != null) {
          tickers = [resolution.ticker!];
        } else if (resolution.matches != null) {
          tickerAmbiguity = {
            'candidate': candidate,
            'matches': [
              for (final m in resolution.matches!)
                {'symbol': m.symbol, 'description': m.description},
            ],
          };
        }
      }
    }

    if (tickers.isEmpty && fallbackTicker != null) {
      tickers = [fallbackTicker];
    }

    final exploreTickers = <String, Object?>{};

    for (final ticker in tickers) {
      exploreTickers[ticker] = await _buildTickerEntry(
        ticker: ticker,
        quoteRepository: quoteRepository,
      );
    }

    final snapshot = <String, Object?>{
      'mode': 'explore',
      'data_source': 'yahoo_finance',
      'as_of': timestamp,
      'explore_tickers': exploreTickers,
    };

    if (marketProxyTicker != null) {
      snapshot['market_proxy_ticker'] = marketProxyTicker;
      snapshot['market_proxy_label'] =
          'S&P 500 (ETF SPY como referencia del mercado estadounidense)';
    }

    if (tickerAmbiguity != null) {
      snapshot['explore_ticker_ambiguous'] = tickerAmbiguity;
    }

    final portfolioFit = _buildPortfolioFit(summary, tickers);
    if (portfolioFit != null) {
      snapshot['portfolio_fit'] = portfolioFit;
    }

    var enriched = snapshot;
    if (earningsAllowed) {
      if (earningsEnricher != null) {
        enriched = await earningsEnricher.enrich(snapshot: enriched);
      }
    } else if (exploreTickers.isNotEmpty) {
      // Sin esto, un usuario sin acceso por plan y uno para el que
      // Finnhub genuinamente no tiene datos ven el mismo silencio en el
      // snapshot — el modelo no puede distinguir "no tenés acceso" de
      // "no hay información" si ninguno de los dos casos deja rastro.
      enriched = {
        ...enriched,
        'earnings_calendar': <String, Object?>{},
        'earnings_calendar_status': 'locked',
      };
    }

    if (newsAllowed) {
      if (newsEnricher != null) {
        enriched = await newsEnricher.enrich(
          snapshot: enriched,
          userMessage: userMessage,
        );
      }
    } else if (isNewsQuery(userMessage)) {
      enriched = {
        ...enriched,
        'news_sources': <Object?>[],
        'news_enrichment': 'locked',
      };
    }

    return enriched;
  }

  static Future<Map<String, Object?>> _buildTickerEntry({
    required String ticker,
    required QuoteRepository quoteRepository,
  }) async {
    final priceResult = await quoteRepository.getCurrentPrice(ticker);
    if (priceResult.isLeft()) {
      return {'fetch_ok': false};
    }

    final currentPrice = priceResult.getOrElse(() => 0.0);
    final candlesResult = await quoteRepository.getHistoricalDaily(ticker);
    final history = candlesResult.fold(
      (_) => <PriceCandle>[],
      (list) => list,
    );

    final periodsMap = <String, Object?>{};
    for (final entry in _periods.entries) {
      final move = TickerPeriodUtils.moveForDuration(
        history,
        entry.value.duration,
      );
      periodsMap[entry.key] = {
        'change_pct': _round2(move.changePct),
        'price_start': _round2(move.priceStart),
        'price_end': _round2(move.priceEnd),
        'has_sufficient_history': move.hasSufficientHistory,
        'label_es': entry.value.labelEs,
      };
    }

    return {
      'current_price': _round2(currentPrice),
      'fetch_ok': true,
      'periods': periodsMap,
    };
  }

  static Map<String, Object?>? _buildPortfolioFit(
    PortfolioSummary? summary,
    List<String> extractedTickers,
  ) {
    if (summary == null || summary.valuations.isEmpty) return null;

    final total = summary.totalValue;
    final weightPctByTicker = <String, double>{};

    for (final valuation in summary.valuations) {
      final ticker = valuation.position.ticker;
      if (!extractedTickers.contains(ticker)) continue;
      final weightPct = total > 0 ? (valuation.marketValue / total) * 100 : 0.0;
      weightPctByTicker[ticker] = _round2(weightPct);
    }

    final fit = <String, Object?>{
      'has_open_positions': true,
    };

    if (weightPctByTicker.isNotEmpty) {
      fit['weight_pct'] = weightPctByTicker;
    }

    return fit;
  }

  static double _round2(double value) =>
      double.parse(value.toStringAsFixed(2));
}
