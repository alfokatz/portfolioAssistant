import 'package:portfolio_assistant/domain/entities/investor_profile.dart';

/// Cruza candidatos de invest con el perfil de inversor: qué tickers
/// proponer cuando el usuario no nombró ninguno, y si cada candidato encaja
/// con su tolerancia al riesgo. Todo determinístico — el modelo solo cita
/// `risk_level`/`matches_profile`, nunca los decide.
abstract final class ProfileCandidateMatcher {
  static const riskDefensive = 'defensivo';
  static const riskCore = 'intermedio';
  static const riskGrowth = 'crecimiento';

  /// Volatilidad relativa aproximada, solo para el universo que ya conoce
  /// `tickerSectorMap`. Un ticker fuera del mapa queda sin clasificar
  /// (`risk_level: null`) en vez de adivinarlo.
  static const _riskLevelByTicker = <String, String>{
    'JNJ': riskDefensive,
    'PG': riskDefensive,
    'KO': riskDefensive,
    'PEP': riskDefensive,
    'PFE': riskDefensive,
    'MRK': riskDefensive,
    'ABBV': riskDefensive,
    'UNH': riskDefensive,
    'WMT': riskDefensive,
    'COST': riskDefensive,
    'MCD': riskDefensive,
    'AAPL': riskCore,
    'MSFT': riskCore,
    'GOOGL': riskCore,
    'GOOG': riskCore,
    'ORCL': riskCore,
    'CRM': riskCore,
    'INTC': riskCore,
    'JPM': riskCore,
    'BAC': riskCore,
    'GS': riskCore,
    'MS': riskCore,
    'V': riskCore,
    'MA': riskCore,
    'XOM': riskCore,
    'CVX': riskCore,
    'COP': riskCore,
    'SLB': riskCore,
    'HD': riskCore,
    'NKE': riskCore,
    'NVDA': riskGrowth,
    'TSLA': riskGrowth,
    'AMD': riskGrowth,
    'META': riskGrowth,
    'AMZN': riskGrowth,
  };

  static const _matchingLevels = <RiskTolerance, Set<String>>{
    RiskTolerance.conservative: {riskDefensive},
    RiskTolerance.moderate: {riskDefensive, riskCore},
    RiskTolerance.aggressive: {riskCore, riskGrowth},
  };

  static String? riskLevelFor(String ticker) =>
      _riskLevelByTicker[ticker.toUpperCase()];

  /// `null` sin perfil o con un ticker sin clasificar.
  static bool? matchesProfile(String ticker, InvestorProfile? profile) {
    if (profile == null) return null;
    final level = riskLevelFor(ticker);
    if (level == null) return null;
    return _matchingLevels[profile.risk]!.contains(level);
  }

  /// Candidatos por defecto (el usuario no nombró tickers ni sector). Sin
  /// perfil → `null`, y el builder usa su lista genérica de siempre.
  static List<String>? defaultCandidatesFor(InvestorProfile? profile) {
    if (profile == null) return null;
    switch (profile.objective) {
      case InvestmentObjective.income:
        return const ['JNJ', 'KO', 'PG', 'JPM'];
      case InvestmentObjective.preservation:
        return const ['JNJ', 'PG', 'KO', 'MSFT'];
      case InvestmentObjective.growth:
      case InvestmentObjective.specificGoal:
        break;
    }
    return switch (profile.risk) {
      RiskTolerance.conservative => const ['JNJ', 'PG', 'KO', 'MSFT'],
      RiskTolerance.moderate => const ['MSFT', 'JNJ', 'JPM', 'COST'],
      RiskTolerance.aggressive => const ['NVDA', 'AMZN', 'META', 'MSFT'],
    };
  }
}
