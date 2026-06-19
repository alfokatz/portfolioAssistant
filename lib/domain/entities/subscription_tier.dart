enum SubscriptionTier {
  free,
  premium,
  gold;

  int get monthlyQuota => switch (this) {
        SubscriptionTier.free => 20,
        SubscriptionTier.premium => 500,
        SubscriptionTier.gold => 1000,
      };

  static SubscriptionTier fromStorageString(String? value) {
    return SubscriptionTier.values.firstWhere(
      (tier) => tier.name == value,
      orElse: () => SubscriptionTier.free,
    );
  }

  String toStorageString() => name;
}
