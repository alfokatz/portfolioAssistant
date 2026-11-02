import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/subscription/config/subscription_catalog.dart';

/// Precio de un plan en un período, tal como lo da la tienda.
class TierPrice {
  const TierPrice({
    required this.priceString,
    required this.price,
    required this.currencyCode,
  });

  /// `storeProduct.priceString`, localizado por la tienda ("US$4,99").
  final String priceString;
  final double price;
  final String currencyCode;

  @override
  bool operator ==(Object other) =>
      other is TierPrice &&
      other.priceString == priceString &&
      other.price == price &&
      other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(priceString, price, currencyCode);
}

/// Lo que el paywall puede ofrecer: precio por plan y período. Vacía si
/// RevenueCat no está configurado o falló (la hoja se ve igual, sin precio).
class PaywallOffer {
  const PaywallOffer(this.prices);

  static const empty = PaywallOffer({});

  final Map<SubscriptionTier, Map<BillingPeriod, TierPrice>> prices;

  TierPrice? priceOf(SubscriptionTier tier, BillingPeriod period) =>
      prices[tier]?[period];

  /// El selector Mensual/Anual aparece solo si TODOS los tiers visibles
  /// tienen anual y mensual.
  bool hasAnnualFor(Iterable<SubscriptionTier> tiers) =>
      tiers.isNotEmpty &&
      tiers.every(
        (t) =>
            priceOf(t, BillingPeriod.monthly) != null &&
            priceOf(t, BillingPeriod.annual) != null,
      );

  /// floor((1 - anual / (12 × mensual)) × 100). null si falta alguno, si
  /// las monedas difieren o si da < 1.
  int? annualSavingsPercent(SubscriptionTier tier) {
    final monthly = priceOf(tier, BillingPeriod.monthly);
    final annual = priceOf(tier, BillingPeriod.annual);
    if (monthly == null || annual == null) return null;
    if (monthly.currencyCode != annual.currencyCode) return null;
    if (monthly.price <= 0 || annual.price <= 0) return null;
    // Redondeo a 6 decimales antes del floor: 59,88 / 71,88 no tiene que
    // dar 16,999999 → 16.
    final raw = (1 - annual.price / (12 * monthly.price)) * 100;
    final percent = (double.parse(raw.toStringAsFixed(6))).floor();
    return percent < 1 ? null : percent;
  }

  /// Arma la oferta desde el offering actual de RevenueCat.
  static PaywallOffer fromOffering(Offering offering) {
    final prices = <SubscriptionTier, Map<BillingPeriod, TierPrice>>{};
    for (final tier in const [SubscriptionTier.premium, SubscriptionTier.gold]) {
      for (final period in BillingPeriod.values) {
        final product = packageFor(offering, tier, period)?.storeProduct;
        if (product == null) continue;
        (prices[tier] ??= {})[period] = TierPrice(
          priceString: product.priceString,
          price: product.price,
          currencyCode: product.currencyCode,
        );
      }
    }
    return PaywallOffer(prices);
  }

  /// El package de un plan y período: por package id; si no, por product id
  /// exacto o con el base plan de Google Play (`producto:baseplan`).
  static Package? packageFor(
    Offering offering,
    SubscriptionTier tier,
    BillingPeriod period,
  ) {
    if (tier == SubscriptionTier.free) return null;
    final byId = offering.getPackage(
      SubscriptionCatalog.packageIdFor(tier, period),
    );
    if (byId != null) return byId;

    final productId = SubscriptionCatalog.productIdFor(tier, period);
    for (final package in offering.availablePackages) {
      final id = package.storeProduct.identifier;
      if (id == productId || id.startsWith('$productId:')) return package;
    }
    return null;
  }
}
