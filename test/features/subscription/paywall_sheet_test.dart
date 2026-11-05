// Paywall: qué muestra según el motivo (planes, medidor, términos, selector
// Mensual/Anual) y qué registra en product_events (paywall_viewed,
// paywall_plan_tapped, purchase_result, paywall_dismissed). Textos por key
// (sin traducciones cargadas); los textos reales en
// paywall_sheet_copy_test.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_skeleton.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/subscription/config/subscription_catalog.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/paywall_offer.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/features/subscription/config/paywall_source.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/segmented_choice.dart';

import 'paywall_test_harness.dart';

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.close_rounded));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(() => PortyAvatar.ambientMotion = false);

  group('SubscriptionPaywallSheet', () {
    testWidgets('opens at once in Gold with the preview, skeleton prices '
        'and a light haptic', (tester) async {
      final slow = Completer<PaywallOffer>();
      final h = PaywallHarness(tier: SubscriptionTier.premium, slowOffer: slow);
      await h.pump(
        tester,
        reason: PaywallReason.goldRequired,
        source: 'analysis_locked_news',
        preview: (_) => const Text('PREVIEW BAC'),
      );
      await h.open(tester);

      expect(h.haptics, [PortyHapticPattern.light]);
      expect(find.text('PREVIEW BAC'), findsOneWidget);
      // Solo Gold (se abrió desde algo de Gold), con su lista de la matriz.
      expect(find.text('paywall_upgrade_gold'), findsOneWidget);
      expect(find.text('paywall_upgrade_premium'), findsNothing);
      expect(find.text('plan_feature_company_analysis'), findsOneWidget);
      // Los precios todavía no llegaron: skeleton en su lugar.
      expect(find.byType(QaSkeleton), findsOneWidget);

      slow.complete(monthlyOffer);
      await tester.pump();
      await tester.pump();
      // Una vez visible, el skeleton se queda al menos 400 ms (no parpadea).
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(QaSkeleton), findsNothing);
      expect(find.text('paywall_price_per_month'), findsOneWidget);
    });

    testWidgets('opening logs paywall_viewed with the 6 props', (tester) async {
      final h = PaywallHarness(used: 7, limit: 20);
      await h.pump(tester, reason: PaywallReason.positionLimit);
      await h.open(tester);

      expect(h.events.of(ProductEvent.paywallViewed), [
        {
          'reason': 'positionLimit',
          'source': 'add_position_limit',
          'tier': 'free',
          'visible_tiers': ['premium', 'gold'],
          'queries_used': 7,
          'queries_limit': 20,
        },
      ]);
    });

    testWidgets('paywall_viewed carries locked_feature when it comes', (
      tester,
    ) async {
      final h = PaywallHarness();
      await h.pump(
        tester,
        reason: PaywallReason.heldNews,
        source: 'chat_turn_locked_held_news',
        lockedFeature: PlanFeature.heldNews,
      );
      await h.open(tester);

      final viewed = h.events.of(ProductEvent.paywallViewed).single;
      expect(viewed['locked_feature'], 'held_news');
      expect(viewed['reason'], 'heldNews');
    });

    testWidgets('paywall_viewed has no locked_feature when none is given', (
      tester,
    ) async {
      final h = PaywallHarness();
      await h.pump(tester, reason: PaywallReason.plans, source: 'settings');
      await h.open(tester);

      expect(
        h.events
            .of(ProductEvent.paywallViewed)
            .single
            .containsKey('locked_feature'),
        isFalse,
      );
    });

    testWidgets('a Premium reason opens with Premium first, badge on it and '
        'both promises', (tester) async {
      final h = PaywallHarness(offer: monthlyOffer);
      await h.pump(tester, reason: PaywallReason.marketDataLocked);
      await h.open(tester);

      final premium = tester.getTopLeft(find.text('paywall_upgrade_premium'));
      final gold = tester.getTopLeft(find.text('paywall_upgrade_gold'));
      expect(premium.dy, lessThan(gold.dy));
      // Un solo badge, en la primera tarjeta.
      expect(find.text('paywall_recommended'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('paywall_recommended')).dy,
        lessThan(premium.dy),
      );
      expect(find.text('paywall_premium_promise'), findsOneWidget);
      expect(find.text('paywall_gold_promise'), findsOneWidget);
    });

    testWidgets('a Gold reason from Free shows only Gold, no badge', (
      tester,
    ) async {
      final h = PaywallHarness(offer: monthlyOffer);
      await h.pump(tester, reason: PaywallReason.goldRequired);
      await h.open(tester);

      expect(find.text('paywall_upgrade_gold'), findsOneWidget);
      expect(find.text('paywall_upgrade_premium'), findsNothing);
      expect(find.text('paywall_recommended'), findsNothing);
      expect(find.text('paywall_gold_promise'), findsOneWidget);
    });

    testWidgets('Gold plan card ends with "everything in Premium"', (
      tester,
    ) async {
      final h = PaywallHarness(offer: monthlyOffer);
      await h.pump(tester, reason: PaywallReason.goldRequired);
      await h.open(tester);

      final last = tester.getTopLeft(find.text('plan_feature_earnings'));
      final all = tester.getTopLeft(
        find.text('plan_feature_everything_premium'),
      );
      expect(all.dy, greaterThan(last.dy));
    });

    testWidgets('closing without buying logs paywall_dismissed', (
      tester,
    ) async {
      final h = PaywallHarness();
      await h.pump(tester, reason: PaywallReason.plans, source: 'settings');
      await h.open(tester);
      await _close(tester);

      final dismissed = h.events.of(ProductEvent.paywallDismissed).single;
      expect(dismissed['source'], 'settings');
      expect(dismissed['seconds_open'], isA<int>());
      expect(dismissed['tapped_plan'], false);
    });

    for (final (result, expected) in <(RevenueCatPurchaseResult, Map)>[
      (const RevenueCatPurchaseCancelled(), {'result': 'cancelled'}),
      (const RevenueCatPurchaseNotConfigured(), {'result': 'not_configured'}),
      (
        const RevenueCatPurchaseFailed('networkError', 'offline'),
        {'result': 'failed', 'error_code': 'networkError'},
      ),
    ]) {
      testWidgets('tapping a plan logs plan_tapped and purchase_result '
          '${expected['result']}', (tester) async {
        final h = PaywallHarness(offer: monthlyOffer);
        h.revenueCat.purchaseResult = result;
        await h.pump(tester, reason: PaywallReason.positionLimit);
        await h.open(tester);

        await tester.tap(find.text('paywall_upgrade_premium'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));

        expect(h.revenueCat.purchases, ['premium:monthly:add_position_limit']);
        expect(h.events.of(ProductEvent.paywallPlanTapped), [
          {
            'tier': 'premium',
            'period': 'monthly',
            'source': 'add_position_limit',
          },
        ]);
        expect(h.events.of(ProductEvent.purchaseResult), [
          {
            'action': 'purchase',
            'tier': 'premium',
            'period': 'monthly',
            'source': 'add_position_limit',
            ...expected,
          },
        ]);

        await _close(tester);
        expect(
          h.events.of(ProductEvent.paywallDismissed).single['tapped_plan'],
          true,
        );
      });
    }

    testWidgets('a successful purchase closes the sheet without '
        'paywall_dismissed', (tester) async {
      var upgraded = 0;
      final h = PaywallHarness(offer: monthlyOffer);
      h.revenueCat.purchaseResult = const RevenueCatPurchaseSuccess();
      await h.pump(
        tester,
        reason: PaywallReason.positionLimit,
        onUpgraded: () => upgraded++,
      );
      await h.open(tester);

      await tester.tap(find.text('paywall_upgrade_gold'));
      // La suscripción reintenta hasta ~10 s esperando al webhook.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(h.events.of(ProductEvent.purchaseResult).single, {
        'action': 'purchase',
        'tier': 'gold',
        'period': 'monthly',
        'source': 'add_position_limit',
        'result': 'success',
      });
      expect(find.text('paywall_upgrade_gold'), findsNothing);
      expect(upgraded, 1);
      expect(h.events.of(ProductEvent.paywallDismissed), isEmpty);
    });

    testWidgets('dragging the sheet closed mid-purchase is not '
        'paywall_dismissed and still upgrades', (tester) async {
      var upgraded = 0;
      final h = PaywallHarness(offer: monthlyOffer);
      h.revenueCat.purchaseResult = const RevenueCatPurchaseSuccess();
      await h.pump(
        tester,
        reason: PaywallReason.positionLimit,
        onUpgraded: () => upgraded++,
      );
      await h.open(tester);

      await tester.tap(find.text('paywall_upgrade_gold'));
      await tester.pump(const Duration(seconds: 1));
      // Mientras la suscripción espera al webhook, el usuario arrastra la hoja:
      // BottomSheet.onClosing hace pop aunque PopScope diga canPop: false.
      await tester.fling(
        find.byType(SubscriptionPaywallSheet),
        const Offset(0, 900),
        3000,
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(find.byType(SubscriptionPaywallSheet), findsNothing);
      expect(h.events.of(ProductEvent.paywallDismissed), isEmpty);
      expect(
        h.events.of(ProductEvent.purchaseResult).single['result'],
        'success',
      );
      expect(upgraded, 1);
    });

    testWidgets('restore logs purchase_result with action restore', (
      tester,
    ) async {
      final h = PaywallHarness();
      h.revenueCat.restoreResult = const RevenueCatPurchaseFailed(
        'storeProblemError',
      );
      await h.pump(tester, reason: PaywallReason.plans, source: 'settings');
      await h.open(tester);

      await tester.tap(find.text('settings_restore_purchases'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(h.revenueCat.restores, 1);
      expect(h.events.of(ProductEvent.purchaseResult), [
        {
          'action': 'restore',
          'source': 'settings',
          'result': 'failed',
          'error_code': 'storeProblemError',
        },
      ]);
    });

    testWidgets('a successful restore does not log paywall_dismissed', (
      tester,
    ) async {
      final h = PaywallHarness();
      h.revenueCat.restoreResult = const RevenueCatPurchaseSuccess();
      await h.pump(tester, reason: PaywallReason.plans, source: 'settings');
      await h.open(tester);

      await tester.tap(find.text('settings_restore_purchases'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(
        h.events.of(ProductEvent.purchaseResult).single['result'],
        'success',
      );
      expect(h.events.of(ProductEvent.paywallDismissed), isEmpty);
    });

    testWidgets('the usage meter only shows for the quota reasons', (
      tester,
    ) async {
      for (final reason in PaywallReason.values) {
        final h = PaywallHarness();
        await h.pump(tester, reason: reason, source: 'test_source');
        await h.open(tester);
        expect(
          find.text('paywall_usage'),
          reason == PaywallReason.quotaExceeded ||
                  reason == PaywallReason.quotaLow
              ? findsOneWidget
              : findsNothing,
          reason: reason.name,
        );
        await _close(tester);
      }
    });

    testWidgets('quotaLow subtitle uses the next plan quota and the date', (
      tester,
    ) async {
      final h = PaywallHarness(clock: () => DateTime.utc(2026, 11, 15));
      await h.pump(
        tester,
        reason: PaywallReason.quotaLow,
        source: PaywallSource.quotaSoft,
      );
      await h.open(tester);
      expect(find.text('paywall_title_quota_low'), findsOneWidget);
      expect(find.text('paywall_subtitle_quota_low'), findsOneWidget);
      expect(find.text('paywall_quota_returns'), findsOneWidget);
      expect(
        h.events.of(ProductEvent.paywallViewed).single['source'],
        'quota_soft',
      );
    });

    test('nextQuotaReset is the 1st of the next UTC month', () {
      expect(nextQuotaReset(DateTime.utc(2026, 11, 15)), DateTime(2026, 12, 1));
      expect(
        nextQuotaReset(DateTime.utc(2026, 12, 31, 23)),
        DateTime(2027, 1, 1),
      );
      // 30/11 22:00 en UTC-5 ya es diciembre en UTC.
      expect(
        nextQuotaReset(DateTime.parse('2026-11-30T22:00:00-05:00')),
        DateTime(2027, 1, 1),
      );
    });

    testWidgets('every reason shows the terms, both links and restore', (
      tester,
    ) async {
      for (final reason in PaywallReason.values) {
        final h = PaywallHarness();
        await h.pump(tester, reason: reason, source: 'test_source');
        await h.open(tester);
        expect(find.text('paywall_terms_block'), findsOneWidget);
        expect(find.text('paywall_terms_link'), findsOneWidget);
        expect(find.text('paywall_privacy_link'), findsOneWidget);
        expect(find.text('settings_restore_purchases'), findsOneWidget);
        // Sin precio no hay línea de renovación en las cards.
        expect(find.text('paywall_renews_line'), findsNothing);
        // Links tocables de al menos 48 dp de alto.
        expect(
          tester.getSize(find.byType(TextButton).at(1)).height,
          greaterThanOrEqualTo(48),
        );
        await _close(tester);
      }
    });

    testWidgets('with prices every card shows the renewal line', (
      tester,
    ) async {
      final h = PaywallHarness(offer: monthlyOffer);
      await h.pump(tester, reason: PaywallReason.plans, source: 'settings');
      await h.open(tester);
      expect(find.text('paywall_renews_line'), findsNWidgets(2));
      expect(find.text('paywall_fair_use'), findsNWidgets(2));
      expect(find.text('paywall_queries_month'), findsNothing);
    });

    // Cada caso en su test: un ProviderScope nuevo en el mismo lugar del
    // árbol no reemplaza los overrides de `overrideWith`.
    for (final (name, offer, enabled) in [
      ('flag off hides the selector even with annual prices', fullOffer, false),
      ('flag on without annual products looks like today', monthlyOffer, true),
    ]) {
      testWidgets('annual selector: $name', (tester) async {
        final h = PaywallHarness(offer: offer, annualEnabled: enabled);
        await h.pump(tester, reason: PaywallReason.positionLimit);
        await h.open(tester);
        expect(find.byType(SegmentedChoice<BillingPeriod>), findsNothing);
        expect(find.text('paywall_price_per_month'), findsNWidgets(2));
        expect(find.text('paywall_price_per_year'), findsNothing);
      });
    }

    testWidgets('annual selector: monthly by default, buys the chosen '
        'period', (tester) async {
      final h = PaywallHarness(offer: fullOffer, annualEnabled: true);
      await h.pump(tester, reason: PaywallReason.positionLimit);
      await h.open(tester);
      expect(find.byType(SegmentedChoice<BillingPeriod>), findsOneWidget);
      // Mensual por defecto.
      expect(find.text('paywall_price_per_month'), findsNWidgets(2));
      expect(find.text('paywall_annual_savings'), findsNothing);

      await tester.tap(find.text('paywall_period_annual'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('paywall_price_per_year'), findsNWidgets(2));
      expect(find.text('paywall_annual_savings'), findsNWidgets(2));

      await tester.tap(find.text('paywall_upgrade_premium'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(h.revenueCat.purchases, ['premium:annual:add_position_limit']);
      expect(
        h.events.of(ProductEvent.paywallPlanTapped).single['period'],
        'annual',
      );
    });

    for (final brightness in Brightness.values) {
      testWidgets('renders at 375 wide in ${brightness.name} with the '
          'selector and the meter', (tester) async {
        final h = PaywallHarness(offer: fullOffer, annualEnabled: true);
        await h.pump(
          tester,
          reason: PaywallReason.quotaExceeded,
          source: 'quota_zero',
          brightness: brightness,
          size: const Size(375, 667),
        );
        await h.open(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('paywall_title_quota'), findsOneWidget);
        expect(find.byType(SegmentedChoice<BillingPeriod>), findsOneWidget);
      });
    }
  });

  group('SubscriptionPaywallSheet.visibleTiersFor', () {
    const free = SubscriptionTier.free;
    const gold = SubscriptionTier.gold;
    const premium = SubscriptionTier.premium;

    test('a Premium user only sees Gold, whatever the reason', () {
      for (final reason in PaywallReason.values) {
        expect(SubscriptionPaywallSheet.visibleTiersFor(reason, premium), [
          gold,
        ], reason: reason.name);
      }
    });

    test('goldRequired only offers Gold', () {
      expect(
        SubscriptionPaywallSheet.visibleTiersFor(
          PaywallReason.goldRequired,
          free,
        ),
        [gold],
      );
    });

    test('every Premium-offer reason opens with Premium for a Free user', () {
      for (final reason in PaywallReason.values) {
        if (reason.offerTier() != SubscriptionTier.premium) continue;
        expect(SubscriptionPaywallSheet.visibleTiersFor(reason, free), [
          premium,
          gold,
        ], reason: reason.name);
      }
    });

    test('plans keeps Gold first', () {
      expect(
        SubscriptionPaywallSheet.visibleTiersFor(PaywallReason.plans, free),
        [gold, premium],
      );
    });
  });

  group('PaywallReason.offerTier', () {
    test('Premium reasons, Gold reason and no preference', () {
      for (final r in [
        PaywallReason.positionLimit,
        PaywallReason.simulations,
        PaywallReason.goals,
        PaywallReason.allocationPlan,
        PaywallReason.marketDataLocked,
        PaywallReason.brokerSync,
        PaywallReason.priceAlerts,
        PaywallReason.benchmark,
        PaywallReason.watchlistLimit,
        PaywallReason.heldNews,
      ]) {
        expect(r.offerTier(), SubscriptionTier.premium, reason: r.name);
      }
      expect(PaywallReason.goldRequired.offerTier(), SubscriptionTier.gold);
      expect(PaywallReason.plans.offerTier(), isNull);
    });

    test('quota reasons offer Premium only from Free', () {
      for (final r in [PaywallReason.quotaExceeded, PaywallReason.quotaLow]) {
        expect(r.offerTier(), SubscriptionTier.premium);
        expect(r.offerTier(currentTier: SubscriptionTier.premium), isNull);
      }
    });
  });
}
