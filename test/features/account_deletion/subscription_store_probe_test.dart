// Reglas de DeletionStoreNotice (spec §3.5, compliance §6.1-6.2).
// Correr: flutter test test/features/account_deletion
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/account_deletion/data/subscription_store_probe.dart';
import 'package:portfolio_assistant/features/account_deletion/domain/account_deletion.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Store;

SubscriptionStoreProbe _probe({
  bool configured = true,
  SubscriptionTier tier = SubscriptionTier.free,
  Future<List<Store>> Function()? stores,
  Duration timeout = const Duration(seconds: 3),
}) => SubscriptionStoreProbe(
  isConfigured: () => configured,
  serverTier: () => tier,
  activeStores: stores ?? () async => const [],
  timeout: timeout,
);

void main() {
  group('SubscriptionStoreProbe.notice', () {
    test('app store and mac app store -> appStore', () async {
      for (final s in [Store.appStore, Store.macAppStore]) {
        expect(
          await _probe(stores: () async => [s]).notice(),
          DeletionStoreNotice.appStore,
        );
      }
    });

    test('play store -> googlePlay', () async {
      expect(
        await _probe(stores: () async => [Store.playStore]).notice(),
        DeletionStoreNotice.googlePlay,
      );
    });

    test('promotional only -> none', () async {
      expect(
        await _probe(stores: () async => [Store.promotional]).notice(),
        DeletionStoreNotice.none,
      );
    });

    test('any other store -> generic', () async {
      for (final s in [Store.stripe, Store.amazon, Store.unknownStore]) {
        expect(
          await _probe(stores: () async => [s]).notice(),
          DeletionStoreNotice.generic,
        );
      }
    });

    test('no active entitlements -> none', () async {
      expect(await _probe().notice(), DeletionStoreNotice.none);
    });

    test('promotional next to a paid store: the paid store wins', () async {
      expect(
        await _probe(
          stores: () async => [Store.promotional, Store.playStore],
        ).notice(),
        DeletionStoreNotice.googlePlay,
      );
    });

    test('different paid stores -> generic', () async {
      expect(
        await _probe(
          stores: () async => [Store.appStore, Store.playStore],
        ).notice(),
        DeletionStoreNotice.generic,
      );
    });

    test(
      'not configured: generic if the server tier is paid, else none',
      () async {
        expect(
          await _probe(configured: false, tier: SubscriptionTier.gold).notice(),
          DeletionStoreNotice.generic,
        );
        expect(
          await _probe(configured: false).notice(),
          DeletionStoreNotice.none,
        );
      },
    );

    test('RevenueCat throws: same fallback by server tier', () async {
      Future<List<Store>> boom() async => throw StateError('x');
      expect(
        await _probe(stores: boom, tier: SubscriptionTier.premium).notice(),
        DeletionStoreNotice.generic,
      );
      expect(await _probe(stores: boom).notice(), DeletionStoreNotice.none);
    });

    test('RevenueCat times out: falls back', () async {
      final never = Completer<List<Store>>();
      final notice =
          await _probe(
            stores: () => never.future,
            tier: SubscriptionTier.premium,
            timeout: const Duration(milliseconds: 10),
          ).notice();
      expect(notice, DeletionStoreNotice.generic);
    });
  });

  group('DeletionStoreNotice', () {
    test('names and links', () {
      expect(DeletionStoreNotice.appStore.storeName, 'App Store');
      expect(
        DeletionStoreNotice.appStore.manageUrl.toString(),
        'https://apps.apple.com/account/subscriptions',
      );
      expect(DeletionStoreNotice.googlePlay.storeName, 'Google Play');
      expect(
        DeletionStoreNotice.googlePlay.manageUrl.toString(),
        'https://play.google.com/store/account/subscriptions',
      );
      expect(DeletionStoreNotice.generic.manageUrl, isNull);
    });
  });
}
