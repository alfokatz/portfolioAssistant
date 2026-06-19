import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/subscription/config/subscription_catalog.dart';

void main() {
  group('SubscriptionCatalog', () {
    test('packageIdFor maps paid tiers', () {
      expect(
        SubscriptionCatalog.packageIdFor(SubscriptionTier.premium),
        SubscriptionCatalog.premiumPackageId,
      );
      expect(
        SubscriptionCatalog.packageIdFor(SubscriptionTier.gold),
        SubscriptionCatalog.goldPackageId,
      );
    });

    test('packageIdFor rejects free tier', () {
      expect(
        () => SubscriptionCatalog.packageIdFor(SubscriptionTier.free),
        throwsArgumentError,
      );
    });
  });
}
