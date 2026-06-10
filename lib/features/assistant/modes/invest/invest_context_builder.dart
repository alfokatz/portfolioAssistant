import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/utils/ticker_period_utils.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/ticker_extractor.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/budget_extractor.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/invest_fit_scorer.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/sector_concentration_checker.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/ticker_sector_map.dart';

/// Construye el snapshot de contexto para modo invest.
abstract final class InvestContextBuilder {
  static const _maxCandidates = 4;

  static const _keywordCandidates = <String, List<String>>{
    'tech': ['NVDA', 'MSFT', 'AAPL'],
    'tecnolog': ['NVDA', 'MSFT', 'AAPL'],
    'energy': ['XOM', 'CVX', 'COP'],
    'energ': ['XOM', 'CVX', 'COP'],
    'petrol': ['XOM', 'CVX', 'COP'],
    'financ': ['JPM', 'BAC', 'GS'],
    'bank': ['JPM', 'BAC', 'GS'],
    'consumer': ['AMZN', 'TSLA', 'COST'],
    'consum': ['AMZN', 'TSLA', 'COST'],
    'health': ['JNJ', 'UNH', 'PFE'],
    'salud': ['JNJ', 'UNH', 'PFE'],
  };

  static const _defaultCandidates = ['NVDA', 'MSFT', 'AAPL', 'JPM'];

  static Future<Map<String, Object?>> build({
    required String userMessage,
    required QuoteRepository quoteRepository,
    PortfolioSummary? summary,
    double? riskProfile,
    DateTime? asOf,
  }) async {
    final timestamp = (asOf ?? DateTime.now()).toUtc().toIso8601String();
    final budget = BudgetExtractor.extractBudgetUsd(userMessage);
    final concentration = SectorConcentrationChecker.fromSummary(summary);
    final candidates = _resolveCandidates(userMessage);

    final candidateEntries = <Map<String, Object?>>[];
    for (final ticker in candidates) {
      candidateEntries.add(
        await _buildCandidate(
          ticker: ticker,
          quoteRepository: quoteRepository,
          hasBudget: budget != null,
          concentration: concentration,
        ),
      );
    }

    final snapshot = <String, Object?>{
      'mode': 'invest',
      'data_source': 'yahoo_finance',
      'as_of': timestamp,
      'has_budget': budget != null,
      'budget_usd': budget,
      'risk_profile': riskProfile,
      'sector_concentration': concentration.sectorWeights,
      'concentration_warning': concentration.overweightSector != null,
      'candidates': candidateEntries,
    };

    if (concentration.overweightSector != null) {
      snapshot['overweight_sector'] = concentration.overweightSector;
    }

    return snapshot;
  }

  static List<String> _resolveCandidates(String userMessage) {
    final extracted = TickerExtractor.extractTickers(userMessage);
    if (extracted.isNotEmpty) {
      return extracted.take(_maxCandidates).toList();
    }

    final lower = userMessage.toLowerCase();
    for (final entry in _keywordCandidates.entries) {
      if (lower.contains(entry.key)) {
        return entry.value.take(_maxCandidates).toList();
      }
    }

    return _defaultCandidates.take(_maxCandidates).toList();
  }

  static Future<Map<String, Object?>> _buildCandidate({
    required String ticker,
    required QuoteRepository quoteRepository,
    required bool hasBudget,
    required SectorConcentration concentration,
  }) async {
    final sector = sectorForTicker(ticker) ?? 'Other';
    final sectorOverlapPct = concentration.sectorWeights[sector];
    final addsDiversification =
        concentration.overweightSector == null ||
        sector != concentration.overweightSector;

    final priceResult = await quoteRepository.getCurrentPrice(ticker);
    if (priceResult.isLeft()) {
      return {
        'ticker': ticker,
        'sector': sector,
        'fetch_ok': false,
        'fit_score': computeFitScore(
          fetchOk: false,
          hasBudget: hasBudget,
          addsDiversification: addsDiversification,
          sectorOverlapPct: sectorOverlapPct,
        ),
      };
    }

    final currentPrice = priceResult.getOrElse(() => 0.0);
    final candlesResult = await quoteRepository.getHistoricalDaily(ticker);
    final history = candlesResult.fold(
      (_) => <PriceCandle>[],
      (list) => list,
    );
    final weekMove = TickerPeriodUtils.moveForDuration(
      history,
      const Duration(days: 7),
    );

    return {
      'ticker': ticker,
      'current_price': _round2(currentPrice),
      'week_change_pct': _round2(weekMove.changePct),
      'sector': sector,
      'fetch_ok': true,
      'fit_score': computeFitScore(
        fetchOk: true,
        hasBudget: hasBudget,
        addsDiversification: addsDiversification,
        sectorOverlapPct: sectorOverlapPct,
      ),
    };
  }

  static double _round2(double value) =>
      double.parse(value.toStringAsFixed(2));
}
