import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';

abstract final class AiUsageLimits {
  static const freeMonthly = 20;
  static const premiumMonthly = 500;
  static const goldMonthly = 1000;
  static const newsQueryWeight = 3;
  static const standardQueryWeight = 1;
  static const freePositionLimit = 10;

  static int monthlyQuota(SubscriptionTier tier) => tier.monthlyQuota;
}
