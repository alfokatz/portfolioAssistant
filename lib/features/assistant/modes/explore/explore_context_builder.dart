import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/utils/ticker_period_utils.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/ticker_extractor.dart';

/// Construye el snapshot de contexto para modo explore desde tickers del mensaje.
abstract final class ExploreContextBuilder {
  static const _periods = <String, ({String labelEs, Duration duration})>{
    'day': (labelEs: 'último día', duration: Duration(days: 1)),
    'week': (labelEs: 'últimos 7 días', duration: Duration(days: 7)),
    'month': (labelEs: 'últimos 30 días', duration: Duration(days: 30)),
  };

  static Future<Map<String, Object?>> build({
    required String userMessage,
    required QuoteRepository quoteRepository,
    PortfolioSummary? summary,
    DateTime? asOf,
  }) async {
    final timestamp = (asOf ?? DateTime.now()).toUtc().toIso8601String();
    final tickers = TickerExtractor.extractTickers(userMessage);
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

    final portfolioFit = _buildPortfolioFit(summary, tickers);
    if (portfolioFit != null) {
      snapshot['portfolio_fit'] = portfolioFit;
    }

    return snapshot;
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
