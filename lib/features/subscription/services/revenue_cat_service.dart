import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/subscription/config/subscription_catalog.dart';
import 'package:portfolio_assistant/features/subscription/services/paywall_offer.dart';

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
  const RevenueCatPurchaseFailed(this.code, [String? message])
    : message = message ?? code;

  /// Código corto para los eventos (`error_code`): `offerings_unavailable`,
  /// `package_not_found`, `invalid_tier`, el `PurchasesErrorCode.name` de
  /// RevenueCat o `unknown`. Nunca el mensaje libre de la tienda.
  final String code;

  /// Detalle para debug (puede traer el texto de la tienda).
  final String message;
}

class RevenueCatService {
  /// Los parámetros son costuras para tests (`configuredForTest` hace de
  /// cuenta que [configure] anduvo); en la app van los de [Purchases].
  RevenueCatService({
    Future<Offerings> Function()? getOfferings,
    Future<void> Function(Map<String, String> attributes)? setAttributes,
    Future<void> Function(Package package)? purchasePackage,
    Future<void> Function()? restorePurchases,
    bool configuredForTest = false,
  }) : _getOfferings = getOfferings ?? Purchases.getOfferings,
       _setAttributes = setAttributes ?? Purchases.setAttributes,
       _purchasePackage =
           purchasePackage ??
           ((package) => Purchases.purchase(PurchaseParams.package(package))),
       _restorePurchases = restorePurchases ?? Purchases.restorePurchases,
       _configuredForTest = configuredForTest;

  final Future<Offerings> Function() _getOfferings;
  final Future<void> Function(Map<String, String> attributes) _setAttributes;
  final Future<void> Function(Package package) _purchasePackage;
  final Future<void> Function() _restorePurchases;
  final bool _configuredForTest;

  bool _configured = false;

  bool get _isReady => _configured || _configuredForTest;

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

  /// Compra [tier] en [period]. Antes de comprar deja el atributo
  /// `paywall_source` en el suscriptor (lo lee el webhook); si eso falla,
  /// se compra igual.
  Future<RevenueCatPurchaseResult> purchase(
    SubscriptionTier tier,
    BillingPeriod period, {
    required String source,
  }) async {
    if (!_isReady) {
      return const RevenueCatPurchaseNotConfigured();
    }
    if (tier == SubscriptionTier.free) {
      return const RevenueCatPurchaseFailed('invalid_tier');
    }

    try {
      final current = (await _getOfferings()).current;
      if (current == null) {
        return const RevenueCatPurchaseFailed('offerings_unavailable');
      }

      final package = PaywallOffer.packageFor(current, tier, period);
      if (package == null) {
        return RevenueCatPurchaseFailed(
          'package_not_found',
          'package_not_found:${SubscriptionCatalog.packageIdFor(tier, period)}',
        );
      }

      try {
        await _setAttributes({'paywall_source': source});
      } catch (_) {
        // La atribución nunca frena una compra.
      }
      await _purchasePackage(package);
      return const RevenueCatPurchaseSuccess();
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return const RevenueCatPurchaseCancelled();
      }
      return RevenueCatPurchaseFailed(code.name, e.message);
    } catch (e) {
      return RevenueCatPurchaseFailed('unknown', e.toString());
    }
  }

  /// Precios mensuales y anuales de la tienda ([PaywallOffer.empty] si
  /// RevenueCat no está configurado o falla).
  Future<PaywallOffer> fetchOffer() async {
    if (!_isReady) return PaywallOffer.empty;

    try {
      final current = (await _getOfferings()).current;
      if (current == null) return PaywallOffer.empty;
      return PaywallOffer.fromOffering(current);
    } catch (_) {
      return PaywallOffer.empty;
    }
  }

  Future<RevenueCatPurchaseResult> restorePurchases() async {
    if (!_isReady) {
      return const RevenueCatPurchaseNotConfigured();
    }

    try {
      await _restorePurchases();
      return const RevenueCatPurchaseSuccess();
    } on PlatformException catch (e) {
      return RevenueCatPurchaseFailed(
        PurchasesErrorHelper.getErrorCode(e).name,
        e.message ?? e.code,
      );
    } catch (e) {
      return RevenueCatPurchaseFailed('unknown', e.toString());
    }
  }
}
