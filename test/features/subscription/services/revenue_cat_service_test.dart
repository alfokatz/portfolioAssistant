// RevenueCatService con las costuras de Purchases: el atributo
// `paywall_source` va antes de comprar, el package se elige por plan y
// período, y las fallas llevan un código corto (nunca el texto de la tienda).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/subscription/config/subscription_catalog.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

Package _pkg(String id, String productId, double price) => Package(
  id,
  PackageType.custom,
  StoreProduct(productId, '', '', price, 'US\$$price', 'USD'),
  const PresentedOfferingContext('default', null, null),
);

final _offerings = Offerings(
  const {},
  current: Offering('default', '', const {}, [
    _pkg('premium_monthly', 'portfolio_premium_monthly', 4.99),
    _pkg('premium_annual', 'portfolio_premium_annual', 49.99),
    _pkg('gold_monthly', 'portfolio_gold_monthly', 9.99),
  ]),
);

void main() {
  group('RevenueCatService.purchase', () {
    late List<String> calls;

    RevenueCatService service({
      Offerings? offerings,
      Object? purchaseError,
      Object? attributesError,
    }) => RevenueCatService(
      configuredForTest: true,
      getOfferings: () async => offerings ?? _offerings,
      setAttributes: (attributes) async {
        calls.add('attributes:${attributes['paywall_source']}');
        if (attributesError != null) throw attributesError;
      },
      purchasePackage: (package) async {
        calls.add('purchase:${package.identifier}');
        if (purchaseError != null) throw purchaseError;
      },
    );

    setUp(() => calls = []);

    test('sets paywall_source before buying the annual package', () async {
      final result = await service().purchase(
        SubscriptionTier.premium,
        BillingPeriod.annual,
        source: 'add_position_limit',
      );
      expect(result, isA<RevenueCatPurchaseSuccess>());
      expect(calls, [
        'attributes:add_position_limit',
        'purchase:premium_annual',
      ]);
    });

    test('buys anyway if the attribute fails', () async {
      final result = await service(
        attributesError: Exception('offline'),
      ).purchase(
        SubscriptionTier.gold,
        BillingPeriod.monthly,
        source: 'settings',
      );
      expect(result, isA<RevenueCatPurchaseSuccess>());
      expect(calls.last, 'purchase:gold_monthly');
    });

    test('missing package: package_not_found and no purchase', () async {
      final result = await service().purchase(
        SubscriptionTier.gold,
        BillingPeriod.annual,
        source: 'settings',
      );
      expect((result as RevenueCatPurchaseFailed).code, 'package_not_found');
      expect(calls, isEmpty);
    });

    test('no current offering: offerings_unavailable', () async {
      final result = await service(
        offerings: const Offerings({}),
      ).purchase(
        SubscriptionTier.gold,
        BillingPeriod.monthly,
        source: 'settings',
      );
      expect(
        (result as RevenueCatPurchaseFailed).code,
        'offerings_unavailable',
      );
    });

    test('free tier: invalid_tier', () async {
      final result = await service().purchase(
        SubscriptionTier.free,
        BillingPeriod.monthly,
        source: 'settings',
      );
      expect((result as RevenueCatPurchaseFailed).code, 'invalid_tier');
    });

    test('store errors keep the RevenueCat code, not the message', () async {
      final result = await service(
        purchaseError: PlatformException(
          code: '${PurchasesErrorCode.networkError.index}',
          message: 'The Internet connection appears to be offline.',
        ),
      ).purchase(
        SubscriptionTier.premium,
        BillingPeriod.monthly,
        source: 'settings',
      );
      final failed = result as RevenueCatPurchaseFailed;
      expect(failed.code, 'networkError');
      expect(failed.message, contains('offline'));
    });

    test('user cancel is cancelled, not failed', () async {
      final result = await service(
        purchaseError: PlatformException(
          code: '${PurchasesErrorCode.purchaseCancelledError.index}',
        ),
      ).purchase(
        SubscriptionTier.premium,
        BillingPeriod.monthly,
        source: 'settings',
      );
      expect(result, isA<RevenueCatPurchaseCancelled>());
    });

    test('anything else: unknown', () async {
      final result = await service(
        purchaseError: StateError('boom'),
      ).purchase(
        SubscriptionTier.premium,
        BillingPeriod.monthly,
        source: 'settings',
      );
      expect((result as RevenueCatPurchaseFailed).code, 'unknown');
    });

    test('not configured: not_configured result and empty offer', () async {
      final unconfigured = RevenueCatService(
        getOfferings: () async => _offerings,
      );
      expect(
        await unconfigured.purchase(
          SubscriptionTier.gold,
          BillingPeriod.monthly,
          source: 'settings',
        ),
        isA<RevenueCatPurchaseNotConfigured>(),
      );
      expect((await unconfigured.fetchOffer()).prices, isEmpty);
    });

    test('fetchOffer reads monthly and annual prices', () async {
      final offer = await service().fetchOffer();
      expect(
        offer.priceOf(SubscriptionTier.premium, BillingPeriod.annual)?.price,
        49.99,
      );
      expect(
        offer.priceOf(SubscriptionTier.gold, BillingPeriod.annual),
        isNull,
      );
    });
  });
}
