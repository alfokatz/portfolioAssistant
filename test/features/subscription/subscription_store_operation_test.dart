import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_tracker.dart';
import 'package:portfolio_assistant/features/subscription/config/subscription_catalog.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';

import 'paywall_test_harness.dart';

/// RevenueCat que no contesta hasta que el test lo suelta.
class _HeldRevenueCat extends FakeRevenueCat {
  final purchaseGate = Completer<RevenueCatPurchaseResult>();

  @override
  Future<RevenueCatPurchaseResult> purchase(
    SubscriptionTier tier,
    BillingPeriod period, {
    required String source,
  }) {
    purchases.add(tier.name);
    return purchaseGate.future;
  }
}

void main() {
  SubscriptionNotifier build(FakeRevenueCat rc) => SubscriptionNotifier(
    tracker: AiUsageTracker(repository: FakeSubscriptionRepo()),
    authService: FakeSession(),
    revenueCat: rc,
  );

  test('una compra en curso expone el plan y bloquea restaurar', () async {
    final rc = _HeldRevenueCat();
    final n = build(rc);
    final purchase = n.purchaseTier(SubscriptionTier.gold, source: 'test');

    expect(n.state.purchasingTier, SubscriptionTier.gold);
    expect(n.state.isRestoring, isFalse);
    expect(n.state.isPurchasing, isTrue);

    // Un segundo pedido no arranca otra operación ni pisa la primera.
    expect(await n.restorePurchases(), isA<RevenueCatPurchaseCancelled>());
    expect(rc.restores, 0);
    expect(n.state.purchasingTier, SubscriptionTier.gold);

    rc.purchaseGate.complete(const RevenueCatPurchaseCancelled());
    await purchase;
    expect(n.state.storeOperation, isNull);
    expect(n.state.isPurchasing, isFalse);
  });

  test('restaurar queda en "restaurando" y vuelve a quieto', () async {
    final rc = FakeRevenueCat();
    final n = build(rc);
    final restore = n.restorePurchases();
    expect(n.state.isRestoring, isTrue);
    expect(n.state.purchasingTier, isNull);
    await restore;
    expect(n.state.storeOperation, isNull);
    expect(rc.restores, 1);
  });
}
