import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';

enum SubscriptionTier {
  free,
  premium,
  gold;

  int get monthlyQuota => PlanMatrix.of(this).monthlyQueries;

  static SubscriptionTier fromStorageString(String? value) {
    return SubscriptionTier.values.firstWhere(
      (tier) => tier.name == value,
      orElse: () => SubscriptionTier.free,
    );
  }

  String toStorageString() => name;
}
