// PaywallOffer: precios por plan y período desde el offering de RevenueCat,
// cuándo hay selector Mensual/Anual y el ahorro calculado.
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/subscription/config/subscription_catalog.dart';
import 'package:portfolio_assistant/features/subscription/services/paywall_offer.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

Package _pkg(
  String id,
  String productId,
  double price, {
  String currency = 'USD',
}) => Package(
  id,
  PackageType.custom,
  StoreProduct(productId, '', '', price, 'US\$$price', currency),
  const PresentedOfferingContext('default', null, null),
);

Offering _offering(List<Package> packages) =>
    Offering('default', '', const {}, packages);

const _both = [SubscriptionTier.gold, SubscriptionTier.premium];

void main() {
  group('PaywallOffer.fromOffering', () {
    test('monthly and annual for both tiers: selector and savings', () {
      final offer = PaywallOffer.fromOffering(
        _offering([
          _pkg('premium_monthly', 'portfolio_premium_monthly', 4.99),
          _pkg('premium_annual', 'portfolio_premium_annual', 49.99),
          _pkg('gold_monthly', 'portfolio_gold_monthly', 10),
          _pkg('gold_annual', 'portfolio_gold_annual', 90),
        ]),
      );

      expect(offer.hasAnnualFor(_both), isTrue);
      expect(
        offer.priceOf(SubscriptionTier.premium, BillingPeriod.annual),
        const TierPrice(
          priceString: 'US\$49.99',
          price: 49.99,
          currencyCode: 'USD',
        ),
      );
      // floor((1 - 49,99 / 59,88) × 100) = floor(16,5) = 16
      expect(offer.annualSavingsPercent(SubscriptionTier.premium), 16);
      // 1 - 90 / 120 = 0,25 exacto: no se cae a 24 por el redondeo.
      expect(offer.annualSavingsPercent(SubscriptionTier.gold), 25);
    });

    test('without annual products: no selector, no savings', () {
      final offer = PaywallOffer.fromOffering(
        _offering([
          _pkg('premium_monthly', 'portfolio_premium_monthly', 4.99),
          _pkg('gold_monthly', 'portfolio_gold_monthly', 9.99),
        ]),
      );
      expect(offer.hasAnnualFor(_both), isFalse);
      expect(offer.annualSavingsPercent(SubscriptionTier.gold), isNull);
      expect(
        offer.priceOf(SubscriptionTier.gold, BillingPeriod.monthly)?.price,
        9.99,
      );
    });

    test('annual for only one visible tier: no selector', () {
      final offer = PaywallOffer.fromOffering(
        _offering([
          _pkg('premium_monthly', 'portfolio_premium_monthly', 4.99),
          _pkg('gold_monthly', 'portfolio_gold_monthly', 9.99),
          _pkg('gold_annual', 'portfolio_gold_annual', 99.99),
        ]),
      );
      expect(offer.hasAnnualFor(_both), isFalse);
      // Desde Premium solo se ve Gold, que sí tiene los dos.
      expect(offer.hasAnnualFor([SubscriptionTier.gold]), isTrue);
    });

    test('different currencies: no selector, no savings', () {
      final offer = PaywallOffer.fromOffering(
        _offering([
          _pkg('gold_monthly', 'portfolio_gold_monthly', 9.99),
          _pkg('gold_annual', 'portfolio_gold_annual', 99.99, currency: 'EUR'),
        ]),
      );
      expect(offer.hasAnnualFor([SubscriptionTier.gold]), isFalse);
      expect(offer.annualSavingsPercent(SubscriptionTier.gold), isNull);
    });

    test('savings under 1 % are not shown', () {
      final offer = PaywallOffer.fromOffering(
        _offering([
          _pkg('gold_monthly', 'portfolio_gold_monthly', 10),
          _pkg('gold_annual', 'portfolio_gold_annual', 119.5),
        ]),
      );
      expect(offer.annualSavingsPercent(SubscriptionTier.gold), isNull);
    });

    test('matches Google Play product:baseplan ids when package ids differ', () {
      final offering = _offering([
        _pkg('\$rc_monthly', 'portfolio_premium_monthly:monthly-base', 4.99),
        _pkg('\$rc_annual', 'portfolio_premium_annual:annual-base', 49.99),
        // Prefijo de otro producto: no tiene que confundirse.
        _pkg('other', 'portfolio_gold_monthly_old', 1),
      ]);
      final offer = PaywallOffer.fromOffering(offering);

      expect(
        offer.priceOf(SubscriptionTier.premium, BillingPeriod.monthly)?.price,
        4.99,
      );
      expect(
        offer.priceOf(SubscriptionTier.premium, BillingPeriod.annual)?.price,
        49.99,
      );
      expect(
        offer.priceOf(SubscriptionTier.gold, BillingPeriod.monthly),
        isNull,
      );
      expect(
        PaywallOffer.packageFor(
          offering,
          SubscriptionTier.premium,
          BillingPeriod.annual,
        )?.identifier,
        '\$rc_annual',
      );
    });

    test('empty offer has nothing', () {
      expect(PaywallOffer.empty.hasAnnualFor(_both), isFalse);
      expect(
        PaywallOffer.empty.priceOf(
          SubscriptionTier.gold,
          BillingPeriod.monthly,
        ),
        isNull,
      );
    });
  });
}
