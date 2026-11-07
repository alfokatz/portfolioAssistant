import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';

/// Período de cobro de un plan. El `name` es el valor de `period` en los
/// eventos del paywall (`monthly` / `annual`).
enum BillingPeriod { monthly, annual }

/// Identificadores que deben coincidir con RevenueCat + App Store / Play Store.
///
/// RevenueCat dashboard:
/// - Entitlements: [premiumEntitlement], [goldEntitlement] (el plan lo dan
///   los entitlements: mensual y anual dan el mismo).
/// - Offering `default` con los packages de [packageIdFor].
/// - Product IDs en las tiendas: [productIdFor]. Google Play los devuelve
///   como `producto:baseplan`.
abstract final class SubscriptionCatalog {
  static const premiumEntitlement = 'premium';
  static const goldEntitlement = 'gold';

  static const premiumPackageId = 'premium_monthly';
  static const goldPackageId = 'gold_monthly';
  static const premiumAnnualPackageId = 'premium_annual';
  static const goldAnnualPackageId = 'gold_annual';

  static const premiumProductId = 'portfolio_premium_monthly';
  static const goldProductId = 'portfolio_gold_monthly';
  static const premiumAnnualProductId = 'portfolio_premium_annual';
  static const goldAnnualProductId = 'portfolio_gold_annual';

  static String packageIdFor(
    SubscriptionTier tier,
    BillingPeriod period,
  ) => switch ((tier, period)) {
    (SubscriptionTier.premium, BillingPeriod.monthly) => premiumPackageId,
    (SubscriptionTier.premium, BillingPeriod.annual) => premiumAnnualPackageId,
    (SubscriptionTier.gold, BillingPeriod.monthly) => goldPackageId,
    (SubscriptionTier.gold, BillingPeriod.annual) => goldAnnualPackageId,
    (SubscriptionTier.free, _) =>
      throw ArgumentError('Free tier has no package'),
  };

  static String productIdFor(
    SubscriptionTier tier,
    BillingPeriod period,
  ) => switch ((tier, period)) {
    (SubscriptionTier.premium, BillingPeriod.monthly) => premiumProductId,
    (SubscriptionTier.premium, BillingPeriod.annual) => premiumAnnualProductId,
    (SubscriptionTier.gold, BillingPeriod.monthly) => goldProductId,
    (SubscriptionTier.gold, BillingPeriod.annual) => goldAnnualProductId,
    (SubscriptionTier.free, _) =>
      throw ArgumentError('Free tier has no product'),
  };
}
