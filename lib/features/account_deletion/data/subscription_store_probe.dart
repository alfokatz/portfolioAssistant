import 'dart:async';

import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/account_deletion/domain/account_deletion.dart';

/// Decide qué aviso de suscripción mostrar mirando los entitlements activos
/// de RevenueCat. Las costuras son para tests.
class SubscriptionStoreProbe {
  SubscriptionStoreProbe({
    required bool Function() isConfigured,
    required SubscriptionTier Function() serverTier,
    Future<List<Store>> Function()? activeStores,
    this.timeout = const Duration(seconds: 3),
  }) : _isConfigured = isConfigured,
       _serverTier = serverTier,
       _activeStores = activeStores ?? _purchasesActiveStores;

  final bool Function() _isConfigured;
  final SubscriptionTier Function() _serverTier;
  final Future<List<Store>> Function() _activeStores;
  final Duration timeout;

  static Future<List<Store>> _purchasesActiveStores() async {
    final info = await Purchases.getCustomerInfo();
    return [for (final e in info.entitlements.active.values) e.store];
  }

  Future<DeletionStoreNotice> notice() async {
    // Sin dato de la tienda, el tier del servidor decide: ante la duda, avisa.
    final fallback =
        _serverTier() == SubscriptionTier.free
            ? DeletionStoreNotice.none
            : DeletionStoreNotice.generic;
    if (!_isConfigured()) return fallback;
    try {
      final stores = await _activeStores().timeout(timeout);
      return DeletionStoreNotice.fromStores(stores);
    } catch (_) {
      return fallback;
    }
  }
}
