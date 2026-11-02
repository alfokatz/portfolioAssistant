// Fakes y armado del paywall para los tests de la hoja (y sus screenshots):
// suscripción con plan y cuota fijos, RevenueCat con oferta y resultados a
// elección, y eventos de producto en memoria.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/domain/entities/subscription_status.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/subscription_repository.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_tracker.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/subscription/config/conversion_flags.dart';
import 'package:portfolio_assistant/features/subscription/config/subscription_catalog.dart';
import 'package:portfolio_assistant/features/subscription/providers/revenue_cat_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/paywall_offer.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeSubscriptionRepo implements SubscriptionRepository {
  FakeSubscriptionRepo({
    this.tier = SubscriptionTier.free,
    this.used = 7,
    this.limit = 20,
  });

  final SubscriptionTier tier;
  final int used;
  final int limit;

  @override
  Future<SubscriptionStatus> fetchStatus() async => SubscriptionStatus(
    tier: tier,
    queriesUsed: used,
    queriesLimit: limit,
    month: '2026-11',
  );

  @override
  Future<bool> consumeQuota(int weight) async => true;
}

class FakeSession implements SupabaseAuthService {
  @override
  Session? get currentSession => Session(
    accessToken: 't',
    tokenType: 'bearer',
    user: const User(
      id: 'u',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// RevenueCat sin red: devuelve la oferta y los resultados que se le den y
/// anota cada compra como `tier:period:source`.
class FakeRevenueCat extends RevenueCatService {
  FakeRevenueCat({
    this.offer = PaywallOffer.empty,
    this.purchaseResult = const RevenueCatPurchaseCancelled(),
    this.restoreResult = const RevenueCatPurchaseCancelled(),
    this.slowOffer,
  });

  final PaywallOffer offer;
  RevenueCatPurchaseResult purchaseResult;
  RevenueCatPurchaseResult restoreResult;

  /// Si está, la oferta tarda hasta que se complete.
  final Completer<PaywallOffer>? slowOffer;

  final purchases = <String>[];
  var restores = 0;

  @override
  Future<PaywallOffer> fetchOffer() => slowOffer?.future ?? Future.value(offer);

  @override
  Future<RevenueCatPurchaseResult> purchase(
    SubscriptionTier tier,
    BillingPeriod period, {
    required String source,
  }) async {
    purchases.add('${tier.name}:${period.name}:$source');
    return purchaseResult;
  }

  @override
  Future<RevenueCatPurchaseResult> restorePurchases() async {
    restores++;
    return restoreResult;
  }
}

class FakeProductEvents extends ProductEvents {
  FakeProductEvents() : super(client: () => null, prefs: () => null);
  final logged = <(ProductEvent, Map<String, Object?>)>[];

  @override
  void log(ProductEvent event, [Map<String, Object?> props = const {}]) =>
      logged.add((event, props));

  List<Map<String, Object?>> of(ProductEvent event) => [
    for (final (e, props) in logged)
      if (e == event) props,
  ];
}

TierPrice usd(double price) => TierPrice(
  priceString: 'US\$${price.toStringAsFixed(2)}',
  price: price,
  currencyCode: 'USD',
);

/// Mensuales y anuales de los dos planes (anual ≈ 10 × mensual).
final fullOffer = PaywallOffer({
  SubscriptionTier.premium: {
    BillingPeriod.monthly: usd(4.99),
    BillingPeriod.annual: usd(49.99),
  },
  SubscriptionTier.gold: {
    BillingPeriod.monthly: usd(9.99),
    BillingPeriod.annual: usd(99.99),
  },
});

/// Solo mensuales (lo que hay hoy en las tiendas).
final monthlyOffer = PaywallOffer({
  SubscriptionTier.premium: {BillingPeriod.monthly: usd(4.99)},
  SubscriptionTier.gold: {BillingPeriod.monthly: usd(9.99)},
});

class PaywallHarness {
  PaywallHarness({
    this.tier = SubscriptionTier.free,
    this.used = 7,
    this.limit = 20,
    PaywallOffer? offer,
    this.annualEnabled = false,
    Completer<PaywallOffer>? slowOffer,
  }) : revenueCat = FakeRevenueCat(
         offer: offer ?? PaywallOffer.empty,
         slowOffer: slowOffer,
       );

  final SubscriptionTier tier;
  final int used;
  final int limit;
  final bool annualEnabled;
  final FakeRevenueCat revenueCat;
  final events = FakeProductEvents();
  final haptics = <PortyHapticPattern>[];

  List<Override> get overrides {
    final tracker = AiUsageTracker(
      repository: FakeSubscriptionRepo(tier: tier, used: used, limit: limit),
    );
    return [
      portyHapticsServiceProvider.overrideWithValue(
        PortyHapticsService(
          enabled: true,
          performer: (p) async => haptics.add(p),
        ),
      ),
      aiUsageTrackerProvider.overrideWithValue(tracker),
      revenueCatServiceProvider.overrideWithValue(revenueCat),
      subscriptionProvider.overrideWith(
        (ref) => SubscriptionNotifier(
          tracker: tracker,
          authService: FakeSession(),
          revenueCat: revenueCat,
        ),
      ),
      productEventsProvider.overrideWithValue(events),
      paywallAnnualEnabledProvider.overrideWith((ref) async => annualEnabled),
    ];
  }

  /// Monta un botón "open" que abre el paywall, con el tema real de la app,
  /// a 375 de ancho (iPhone SE) y alto de sobra para tocar todo sin scroll.
  Future<void> pump(
    WidgetTester tester, {
    required PaywallReason reason,
    String source = 'add_position_limit',
    Brightness brightness = Brightness.light,
    WidgetBuilder? preview,
    VoidCallback? onUpgraded,
    Size size = const Size(375, 2200),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final themes = ProviderContainer();
    addTearDown(themes.dispose);
    final theme = themes.read(
      brightness == Brightness.dark
          ? themeDataDarkProvider
          : themeDataLightProvider,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: theme,
          home: Consumer(
            builder:
                (context, ref, _) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed:
                          () => SubscriptionPaywallSheet.show(
                            context,
                            ref,
                            reason: reason,
                            source: source,
                            preview: preview,
                            onUpgraded: onUpgraded,
                          ),
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
    // La suscripción carga (plan y cuota del repo falso).
    await tester.pump();
    await tester.pump();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    // Un frame para que lleguen la oferta y el interruptor (si no, el
    // skeleton del precio arranca a los 300 ms y se queda 400).
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
}
