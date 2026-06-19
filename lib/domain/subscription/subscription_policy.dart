import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_limits.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';

abstract final class SubscriptionPolicy {
  static bool isModeAllowed(SubscriptionTier tier, AssistantMode mode) {
    return switch (mode) {
      AssistantMode.portfolio || AssistantMode.learn => true,
      AssistantMode.explore =>
        tier == SubscriptionTier.premium || tier == SubscriptionTier.gold,
      AssistantMode.invest || AssistantMode.plan =>
        tier == SubscriptionTier.gold,
    };
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

  static bool isNewsAllowed(SubscriptionTier tier) {
    return tier == SubscriptionTier.gold;
  }

  static int queryWeight({required bool isNewsQuery}) {
    return isNewsQuery
        ? AiUsageLimits.newsQueryWeight
        : AiUsageLimits.standardQueryWeight;
  }
}
