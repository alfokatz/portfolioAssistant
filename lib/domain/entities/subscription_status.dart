import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';

class SubscriptionStatus {
  const SubscriptionStatus({
    required this.tier,
    required this.queriesUsed,
    required this.queriesLimit,
    required this.month,
  });

  final SubscriptionTier tier;
  final int queriesUsed;
  final int queriesLimit;
  final String month;

  int get queriesRemaining =>
      (queriesLimit - queriesUsed).clamp(0, queriesLimit);
}
