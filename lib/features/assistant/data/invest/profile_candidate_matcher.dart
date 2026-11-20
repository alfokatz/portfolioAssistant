import 'package:portfolio_assistant/domain/entities/investor_profile.dart';

/// Cruza un candidato con el perfil de inversor. El nivel de riesgo sale de
/// la beta REAL del ticker (volatilidad relativa al mercado, Yahoo), así
/// sirve para cualquier empresa — no hay lista de tickers conocidos. El
/// modelo solo cita `risk_level`/`matches_profile`, nunca los decide.
abstract final class ProfileCandidateMatcher {
  static const riskDefensive = 'defensivo';
  static const riskCore = 'intermedio';
  static const riskGrowth = 'crecimiento';

  /// beta < 0,9 se mueve menos que el mercado; > 1,3, bastante más.
  static const _defensiveBelow = 0.9;
  static const _growthAbove = 1.3;

  static const _matchingLevels = <RiskTolerance, Set<String>>{
    RiskTolerance.conservative: {riskDefensive},
    RiskTolerance.moderate: {riskDefensive, riskCore},
    RiskTolerance.aggressive: {riskCore, riskGrowth},
  };

  /// `null` sin beta (ETF sin dato, ticker nuevo, falla de Yahoo): mejor
  /// "sin clasificar" que adivinar.
  static String? riskLevelForBeta(double? beta) {
    if (beta == null) return null;
    if (beta < _defensiveBelow) return riskDefensive;
    if (beta > _growthAbove) return riskGrowth;
    return riskCore;
  }

  /// `null` sin perfil o sin nivel de riesgo.
  static bool? matchesProfile(String? riskLevel, InvestorProfile? profile) {
    if (profile == null || riskLevel == null) return null;
    return _matchingLevels[profile.risk]!.contains(riskLevel);
  }
}
