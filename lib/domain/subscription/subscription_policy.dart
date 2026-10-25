import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_limits.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';

/// Qué incluye cada plan. El asistente lo consulta por DATO (no por modo):
/// cada tool de datos chequea el predicado que le corresponde al ejecutarse.
/// Todo sale de [PlanMatrix]: acá no se decide nada, solo se nombra.
abstract final class SubscriptionPolicy {
  static bool allows(SubscriptionTier tier, PlanFeature feature) =>
      PlanMatrix.allows(tier, feature);

  /// Precios y variaciones de tickers que el usuario NO tiene en cartera.
  /// La cartera propia está siempre disponible.
  static bool isMarketDataAllowed(SubscriptionTier tier) =>
      allows(tier, PlanFeature.marketData);

  /// Simulación de inversión.
  static bool isInvestSimulationAllowed(SubscriptionTier tier) =>
      allows(tier, PlanFeature.investSimulation);

  /// Metas y proyecciones.
  static bool isGoalsAllowed(SubscriptionTier tier) =>
      allows(tier, PlanFeature.goals);

  static int? positionLimit(SubscriptionTier tier) =>
      PlanMatrix.of(tier).positionLimit;

  static bool isBenchmarkAllowed(SubscriptionTier tier) =>
      allows(tier, PlanFeature.benchmark);

  static bool isNewsAllowed(SubscriptionTier tier) =>
      allows(tier, PlanFeature.news);

  static bool isEarningsAllowed(SubscriptionTier tier) =>
      allows(tier, PlanFeature.earnings);

  static bool isFundamentalsAllowed(SubscriptionTier tier) =>
      allows(tier, PlanFeature.fundamentals);

  static int queryWeight({required bool isNewsQuery}) {
    return isNewsQuery
        ? AiUsageLimits.newsQueryWeight
        : AiUsageLimits.standardQueryWeight;
  }
}
