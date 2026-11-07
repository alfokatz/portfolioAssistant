// Ids de RevenueCat y de las tiendas por plan y período.
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/subscription/config/subscription_catalog.dart';

void main() {
  group('SubscriptionCatalog', () {
    test('packageIdFor maps paid tiers and periods', () {
      expect(
        SubscriptionCatalog.packageIdFor(
          SubscriptionTier.premium,
          BillingPeriod.monthly,
        ),
        'premium_monthly',
      );
      expect(
        SubscriptionCatalog.packageIdFor(
          SubscriptionTier.gold,
          BillingPeriod.monthly,
        ),
        'gold_monthly',
      );
      expect(
        SubscriptionCatalog.packageIdFor(
          SubscriptionTier.premium,
          BillingPeriod.annual,
        ),
        'premium_annual',
      );
      expect(
        SubscriptionCatalog.packageIdFor(
          SubscriptionTier.gold,
          BillingPeriod.annual,
        ),
        'gold_annual',
      );
    });

    test('productIdFor maps paid tiers and periods', () {
      expect(
        SubscriptionCatalog.productIdFor(
          SubscriptionTier.premium,
          BillingPeriod.monthly,
        ),
        'portfolio_premium_monthly',
      );
      expect(
        SubscriptionCatalog.productIdFor(
          SubscriptionTier.gold,
          BillingPeriod.annual,
        ),
        'portfolio_gold_annual',
      );
      expect(
        SubscriptionCatalog.productIdFor(
          SubscriptionTier.premium,
          BillingPeriod.annual,
        ),
        'portfolio_premium_annual',
      );
    });

    test('free tier has no package nor product', () {
      for (final period in BillingPeriod.values) {
        expect(
          () => SubscriptionCatalog.packageIdFor(SubscriptionTier.free, period),
          throwsArgumentError,
        );
        expect(
          () => SubscriptionCatalog.productIdFor(SubscriptionTier.free, period),
          throwsArgumentError,
        );
      }
    });

    test('period names are the wire values of the events', () {
      expect(BillingPeriod.monthly.name, 'monthly');
      expect(BillingPeriod.annual.name, 'annual');
    });
  });
}
