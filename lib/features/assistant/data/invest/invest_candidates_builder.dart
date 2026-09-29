import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/utils/ticker_period_utils.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/invest_fit_scorer.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/profile_candidate_matcher.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/sector_concentration_checker.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/sector_display_name.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/sector_resolver.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/yahoo_company_profile_client.dart';
import 'package:portfolio_assistant/features/assistant/utils/investor_profile_context.dart';

/// Datos reales para una simulación educativa de inversión sobre los
/// candidatos que ELIGIÓ el modelo — cualquier ticker de cualquier industria,
/// sin listas precargadas. Por candidato: precio, variación semanal, sector
/// e industria, beta y nivel de riesgo derivado, encaje con el perfil y
/// puntaje de encaje con la cartera. Más la concentración por sector de la
/// cartera actual.
abstract final class InvestCandidatesBuilder {
  static const maxCandidates = 6;

  static Future<Map<String, Object?>> build({
    required List<String> tickers,
    required QuoteRepository quoteRepository,
    required YahooCompanyProfileClient profileClient,
    double? budgetUsd,
    PortfolioSummary? summary,
    InvestorProfile? investorProfile,
    DateTime? asOf,
  }) async {
    final now = asOf ?? DateTime.now();
    final hasBudget = budgetUsd != null && budgetUsd > 0;
    final candidateTickers =
        tickers
            .map((t) => t.toUpperCase())
            .toSet()
            .take(maxCandidates)
            .toList();
    final portfolioTickers =
        summary?.valuations
            .map((v) => v.position.ticker.toUpperCase())
            .toList() ??
        const <String>[];

    final profiles = await profileClient.fetchProfiles([
      ...portfolioTickers,
      ...candidateTickers,
    ]);
    final sectorByTicker = SectorResolver.fromProfiles([
      ...portfolioTickers,
      ...candidateTickers,
    ], profiles);
    final concentration = SectorConcentrationChecker.fromSummary(
      summary,
      sectorByTicker: sectorByTicker,
    );

    final candidates = await Future.wait(
      candidateTickers.map(
        (ticker) => _buildCandidate(
          ticker: ticker,
          profile: profiles[ticker],
          quoteRepository: quoteRepository,
          hasBudget: hasBudget,
          concentration: concentration,
          investorProfile: investorProfile,
          sector: sectorByTicker[ticker] ?? SectorDisplayName.unclassified,
        ),
      ),
    );

    return {
      'has_budget': hasBudget,
      'budget_usd': hasBudget ? budgetUsd : null,
      'investor_profile': InvestorProfileContext.build(investorProfile, now),
      'sector_concentration': concentration.sectorWeights,
      'concentration_warning': concentration.overweightSector != null,
      if (concentration.overweightSector != null)
        'overweight_sector': concentration.overweightSector,
      'candidates': candidates,
    };
  }

  static Future<Map<String, Object?>> _buildCandidate({
    required String ticker,
    required YahooCompanyProfile? profile,
    required QuoteRepository quoteRepository,
    required bool hasBudget,
    required SectorConcentration concentration,
    required InvestorProfile? investorProfile,
    required String sector,
  }) async {
    final riskLevel = ProfileCandidateMatcher.riskLevelForBeta(profile?.beta);
    final descriptive = <String, Object?>{
      'ticker': ticker,
      'sector': sector,
      if (profile?.industry != null) 'industry': profile!.industry,
      if (profile?.beta != null) 'beta': _round2(profile!.beta!),
      'risk_level': riskLevel,
      'matches_profile': ProfileCandidateMatcher.matchesProfile(
        riskLevel,
        investorProfile,
      ),
    };
    final sectorOverlapPct = concentration.sectorWeights[sector];
    final addsDiversification =
        concentration.overweightSector == null ||
        sector != concentration.overweightSector;

    final priceResult = await quoteRepository.getCurrentPrice(ticker);
    if (priceResult.isLeft()) {
      return {
        ...descriptive,
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
    final history = candlesResult.fold((_) => <PriceCandle>[], (list) => list);
    final weekMove = TickerPeriodUtils.moveForDuration(
      history,
      const Duration(days: 7),
    );

    return {
      ...descriptive,
      'current_price': _round2(currentPrice),
      'week_change_pct': _round2(weekMove.changePct),
      'fetch_ok': true,
      'fit_score': computeFitScore(
        fetchOk: true,
        hasBudget: hasBudget,
        addsDiversification: addsDiversification,
        sectorOverlapPct: sectorOverlapPct,
      ),
    };
  }

  static double _round2(double value) => double.parse(value.toStringAsFixed(2));
}
