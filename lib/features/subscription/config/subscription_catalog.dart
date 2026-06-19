import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';

/// Identificadores que deben coincidir con RevenueCat + App Store / Play Store.
///
/// RevenueCat dashboard:
/// - Entitlements: [premiumEntitlement], [goldEntitlement]
/// - Offering `default` con packages [premiumPackageId], [goldPackageId]
/// - Product IDs en stores: [premiumProductId], [goldProductId]
abstract final class SubscriptionCatalog {
  static const premiumEntitlement = 'premium';
  static const goldEntitlement = 'gold';

  static const premiumPackageId = 'premium_monthly';
  static const goldPackageId = 'gold_monthly';

  static const premiumProductId = 'portfolio_premium_monthly';
  static const goldProductId = 'portfolio_gold_monthly';

  static String packageIdFor(SubscriptionTier tier) => switch (tier) {
        SubscriptionTier.premium => premiumPackageId,
        SubscriptionTier.gold => goldPackageId,
        SubscriptionTier.free => throw ArgumentError('Free tier has no package'),
      };
}
