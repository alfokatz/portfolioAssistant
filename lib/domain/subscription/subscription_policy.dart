import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_limits.dart';

/// Qué incluye cada plan. El asistente lo consulta por DATO (no por modo):
/// cada tool de datos chequea el predicado que le corresponde al ejecutarse.
abstract final class SubscriptionPolicy {
  /// Precios y variaciones de tickers que el usuario NO tiene en cartera.
  /// La cartera propia está siempre disponible.
  static bool isMarketDataAllowed(SubscriptionTier tier) {
    return tier == SubscriptionTier.premium || tier == SubscriptionTier.gold;
  }

  /// Simulación de inversión y planificación de metas.
  static bool isAdviceAllowed(SubscriptionTier tier) {
    return tier == SubscriptionTier.gold;
  }

  static int? positionLimit(SubscriptionTier tier) {
    return switch (tier) {
      SubscriptionTier.free => AiUsageLimits.freePositionLimit,
      SubscriptionTier.premium || SubscriptionTier.gold => null,
    };
  }

  static bool isBenchmarkAllowed(SubscriptionTier tier) {
    return switch (tier) {
      SubscriptionTier.free => false,
      SubscriptionTier.premium || SubscriptionTier.gold => true,
    };
  }

  /// Noticias, calendario de resultados y fundamentals.
  static bool isNewsAllowed(SubscriptionTier tier) {
    return tier == SubscriptionTier.gold;
  }

  static int queryWeight({required bool isNewsQuery}) {
    return isNewsQuery
        ? AiUsageLimits.newsQueryWeight
        : AiUsageLimits.standardQueryWeight;
  }
}
