import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/subscription/config/subscription_catalog.dart';

sealed class RevenueCatPurchaseResult {
  const RevenueCatPurchaseResult();
}

final class RevenueCatPurchaseSuccess extends RevenueCatPurchaseResult {
  const RevenueCatPurchaseSuccess();
}

final class RevenueCatPurchaseCancelled extends RevenueCatPurchaseResult {
  const RevenueCatPurchaseCancelled();
}

final class RevenueCatPurchaseNotConfigured extends RevenueCatPurchaseResult {
  const RevenueCatPurchaseNotConfigured();
}

final class RevenueCatPurchaseFailed extends RevenueCatPurchaseResult {
  const RevenueCatPurchaseFailed(this.message);

  final String message;
}

class RevenueCatService {
  bool _configured = false;

  static bool get isPlatformSupported {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid || Platform.isMacOS;
  }

  String? get _apiKey {
    if (kIsWeb) return null;
    if (Platform.isIOS || Platform.isMacOS) {
      return dotenv.env['REVENUECAT_APPLE_API_KEY']?.trim();
    }
    if (Platform.isAndroid) {
      return dotenv.env['REVENUECAT_GOOGLE_API_KEY']?.trim();
    }
    return null;
  }

  bool get isConfigured => _configured;

  Future<void> configure() async {
    if (!isPlatformSupported) return;
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);
    await Purchases.configure(PurchasesConfiguration(apiKey));
    _configured = true;
  }

  Future<void> logIn(String userId) async {
    if (!_configured) return;
    await Purchases.logIn(userId);
  }

  Future<void> logOut() async {
    if (!_configured) return;
    await Purchases.logOut();
  }

  Future<RevenueCatPurchaseResult> purchaseTier(SubscriptionTier tier) async {
    if (!_configured) {
      return const RevenueCatPurchaseNotConfigured();
    }
    if (tier == SubscriptionTier.free) {
      return const RevenueCatPurchaseFailed('invalid_tier');
    }

    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) {
        return const RevenueCatPurchaseFailed('offerings_unavailable');
      }

      final packageId = SubscriptionCatalog.packageIdFor(tier);
      final package = current.getPackage(packageId) ??
          _findPackageByProductId(current, tier);

      if (package == null) {
        return RevenueCatPurchaseFailed('package_not_found:$packageId');
      }

      await Purchases.purchase(PurchaseParams.package(package));
      return const RevenueCatPurchaseSuccess();
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return const RevenueCatPurchaseCancelled();
      }
      return RevenueCatPurchaseFailed(e.message ?? code.name);
    } catch (e) {
      return RevenueCatPurchaseFailed(e.toString());
    }
  }

  /// Precios localizados desde la store (vacío si RevenueCat no está configurado).
  Future<Map<SubscriptionTier, String>> fetchTierPrices() async {
    if (!_configured) return {};

    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) return {};

      final prices = <SubscriptionTier, String>{};
      for (final tier in [SubscriptionTier.premium, SubscriptionTier.gold]) {
        final packageId = SubscriptionCatalog.packageIdFor(tier);
        final package =
            current.getPackage(packageId) ??
            _findPackageByProductId(current, tier);
        if (package != null) {
          prices[tier] = package.storeProduct.priceString;
        }
      }
      return prices;
    } catch (_) {
      return {};
    }
  }

  Future<RevenueCatPurchaseResult> restorePurchases() async {
    if (!_configured) {
      return const RevenueCatPurchaseNotConfigured();
    }

    try {
      await Purchases.restorePurchases();
      return const RevenueCatPurchaseSuccess();
    } on PlatformException catch (e) {
      return RevenueCatPurchaseFailed(e.message ?? e.code);
    } catch (e) {
      return RevenueCatPurchaseFailed(e.toString());
    }
  }

  Package? _findPackageByProductId(Offering offering, SubscriptionTier tier) {
    final productId = switch (tier) {
      SubscriptionTier.premium => SubscriptionCatalog.premiumProductId,
      SubscriptionTier.gold => SubscriptionCatalog.goldProductId,
      SubscriptionTier.free => null,
    };
    if (productId == null) return null;

    for (final package in offering.availablePackages) {
      if (package.storeProduct.identifier == productId) {
        return package;
      }
    }
    return null;
  }
}
