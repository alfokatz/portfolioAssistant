import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/legal/legal_links.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_limits.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_skeleton.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/subscription/config/conversion_flags.dart';
import 'package:portfolio_assistant/features/subscription/config/paywall_source.dart';
import 'package:portfolio_assistant/features/subscription/config/subscription_catalog.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/paywall_offer.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_gold_theme.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/loading/button_spinner.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/segmented_choice.dart';
import 'package:url_launcher/url_launcher.dart';

/// El paywall: planes visibles según el motivo, precios de la tienda,
/// selector Mensual/Anual (si la tienda trae los anuales y el interruptor
/// `paywall_annual` está prendido) y los términos de la suscripción.
///
/// Mide en `product_events`: `paywall_viewed` al abrir, `paywall_plan_tapped`
/// y `purchase_result` al comprar o restaurar, y `paywall_dismissed` si se
/// cierra sin compra ni restauración exitosa.
class SubscriptionPaywallSheet extends ConsumerStatefulWidget {
  const SubscriptionPaywallSheet({
    super.key,
    required this.reason,
    required this.source,
    this.onUpgraded,
    this.preview,
  });

  final PaywallReason reason;
  final VoidCallback? onUpgraded;

  /// Desde dónde se abrió (ver [PaywallSource]), para medir conversiones.
  final String source;

  /// Gancho visual arriba de los planes (p. ej. la vista previa del
  /// análisis del ticker desde el que se abrió).
  final WidgetBuilder? preview;

  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required PaywallReason reason,
    required String source,
    VoidCallback? onUpgraded,
    WidgetBuilder? preview,
  }) {
    assert(
      PaywallSource.isValid(source) && source != reason.name,
      'PaywallSource inválido: "$source" (ver PaywallSource)',
    );
    final subscription = ref.read(subscriptionProvider);
    if (subscription.tier == SubscriptionTier.gold && !subscription.isLoading) {
      return Future.value();
    }

    ref.invalidate(paywallOfferProvider);
    ref.invalidate(paywallAnnualEnabledProvider);
    // Toque leve al abrir; el de "tocaste algo bloqueado" ya lo dio el
    // widget en el mismo frame del toque.
    PortyHapticsService.maybeOf(context)?.paywallOpened();

    final colors = Theme.of(context).extension<CustomColors>()!;

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimens.radiusXl),
        ),
      ),
      builder:
          (_) => SubscriptionPaywallSheet(
            reason: reason,
            source: source,
            onUpgraded: onUpgraded,
            preview: preview,
          ),
    );
  }

  /// Lo que el paywall lista de cada plan, de la matriz de planes (la misma
  /// fuente que el gating): Gold abre con "Todo lo de Premium".
  static List<String> featureKeysFor(SubscriptionTier tier) => [
    if (tier == SubscriptionTier.gold) 'plan_feature_everything_premium',
    ...PlanMatrix.marketingKeys(tier),
  ];

  /// Planes que se ofrecen: Gold primero; desde Premium solo Gold.
  static List<SubscriptionTier> visibleTiersFor(
    PaywallReason reason,
    SubscriptionTier currentTier,
  ) {
    if (reason == PaywallReason.goldRequired ||
        currentTier == SubscriptionTier.premium) {
      return const [SubscriptionTier.gold];
    }
    return const [SubscriptionTier.gold, SubscriptionTier.premium];
  }

  static String titleKeyFor(PaywallReason reason) => switch (reason) {
    PaywallReason.modeLocked => 'paywall_title_mode_locked',
    PaywallReason.plans => 'paywall_title_plans',
    PaywallReason.positionLimit => 'paywall_title_position_limit',
    PaywallReason.simulations => 'paywall_title_simulations',
    PaywallReason.goals => 'paywall_title_goals',
    PaywallReason.allocationPlan => 'paywall_title_allocation_plan',
    PaywallReason.marketDataLocked => 'paywall_title_market_data',
    PaywallReason.goldRequired => 'paywall_title_gold',
    PaywallReason.quotaExceeded => 'paywall_title_quota',
    PaywallReason.brokerSync => 'paywall_title_broker_sync',
    PaywallReason.priceAlerts => 'paywall_title_price_alerts',
  };

  static String subtitleKeyFor(PaywallReason reason) => switch (reason) {
    PaywallReason.modeLocked => 'paywall_subtitle_mode_locked',
    PaywallReason.plans => 'paywall_subtitle_plans',
    PaywallReason.positionLimit => 'paywall_subtitle_position_limit',
    PaywallReason.simulations => 'paywall_subtitle_simulations',
    PaywallReason.goals => 'paywall_subtitle_goals',
    PaywallReason.allocationPlan => 'paywall_subtitle_allocation_plan',
    PaywallReason.marketDataLocked => 'paywall_subtitle_market_data',
    PaywallReason.goldRequired => 'paywall_subtitle_gold',
    PaywallReason.quotaExceeded => 'paywall_subtitle_quota',
    PaywallReason.brokerSync => 'paywall_subtitle_broker_sync',
    PaywallReason.priceAlerts => 'paywall_subtitle_price_alerts',
  };

  @override
  ConsumerState<SubscriptionPaywallSheet> createState() =>
      _SubscriptionPaywallSheetState();
}

class _SubscriptionPaywallSheetState
    extends ConsumerState<SubscriptionPaywallSheet> {
  late final ProductEvents _events;
  late final DateTime _openedAt;
  BillingPeriod _period = BillingPeriod.monthly;
  bool _tappedPlan = false;

  /// Compró o restauró con éxito: cerrar no es "se fue sin comprar".
  bool _converted = false;

  /// Hay una compra o restauración en curso. Arrastrar la hoja la cierra igual
  /// (`BottomSheet.onClosing` hace `pop`, no `maybePop`), así que cerrar en
  /// ese momento no cuenta como `paywall_dismissed`: el resultado llega por
  /// `purchase_result`.
  bool _inFlight = false;

  String get _source => widget.source;

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    // Se guarda acá: en dispose ya no se puede leer de ref.
    _events = ref.read(productEventsProvider);
    final subscription = ref.read(subscriptionProvider);
    _events.log(ProductEvent.paywallViewed, {
      'reason': widget.reason.name,
      'source': _source,
      'tier': subscription.tier.name,
      'visible_tiers': [
        for (final t in SubscriptionPaywallSheet.visibleTiersFor(
          widget.reason,
          subscription.tier,
        ))
          t.name,
      ],
      'queries_used': subscription.queriesUsed,
      'queries_limit': subscription.queriesLimit,
    });
  }

  @override
  void dispose() {
    if (!_converted && !_inFlight) {
      _events.log(ProductEvent.paywallDismissed, {
        'source': _source,
        'seconds_open': DateTime.now().difference(_openedAt).inSeconds,
        'tapped_plan': _tappedPlan,
      });
    }
    super.dispose();
  }

  /// `result` (y `error_code` si falló) de `purchase_result`.
  static Map<String, Object?> _resultProps(RevenueCatPurchaseResult result) =>
      switch (result) {
        RevenueCatPurchaseSuccess() => {'result': 'success'},
        RevenueCatPurchaseCancelled() => {'result': 'cancelled'},
        RevenueCatPurchaseNotConfigured() => {'result': 'not_configured'},
        RevenueCatPurchaseFailed(:final code) => {
          'result': 'failed',
          'error_code': code,
        },
      };

  Future<void> _purchase(SubscriptionTier tier, BillingPeriod period) async {
    _tappedPlan = true;
    _events.log(ProductEvent.paywallPlanTapped, {
      'tier': tier.name,
      'period': period.name,
      'source': _source,
    });
    _inFlight = true;
    final RevenueCatPurchaseResult result;
    try {
      result = await ref
          .read(subscriptionProvider.notifier)
          .purchaseTier(tier, period: period, source: _source);
    } finally {
      _inFlight = false;
    }
    _events.log(ProductEvent.purchaseResult, {
      'action': 'purchase',
      'tier': tier.name,
      'period': period.name,
      'source': _source,
      ..._resultProps(result),
    });
    if (result is RevenueCatPurchaseSuccess) {
      _converted = true;
      if (!mounted) {
        widget.onUpgraded?.call();
        return;
      }
    }
    if (!mounted) return;

    switch (result) {
      case RevenueCatPurchaseSuccess():
        ref
            .read(alertProvider.notifier)
            .showSuccess(message: 'subscription_purchase_success'.tr());
        Navigator.of(context).pop();
        widget.onUpgraded?.call();
      case RevenueCatPurchaseCancelled():
        break;
      case RevenueCatPurchaseNotConfigured():
        ref
            .read(alertProvider.notifier)
            .showWarning(message: 'settings_upgrade_coming_soon'.tr());
      case RevenueCatPurchaseFailed():
        ref
            .read(alertProvider.notifier)
            .showError(message: 'subscription_purchase_error'.tr());
    }
  }

  Future<void> _restore() async {
    _inFlight = true;
    final RevenueCatPurchaseResult result;
    try {
      result = await ref.read(subscriptionProvider.notifier).restorePurchases();
    } finally {
      _inFlight = false;
    }
    _events.log(ProductEvent.purchaseResult, {
      'action': 'restore',
      'source': _source,
      ..._resultProps(result),
    });
    if (result is RevenueCatPurchaseSuccess) {
      _converted = true;
      if (!mounted) {
        widget.onUpgraded?.call();
        return;
      }
    }
    if (!mounted) return;

    switch (result) {
      case RevenueCatPurchaseSuccess():
        ref
            .read(alertProvider.notifier)
            .showSuccess(message: 'subscription_restore_success'.tr());
        Navigator.of(context).pop();
        widget.onUpgraded?.call();
      case RevenueCatPurchaseCancelled():
        break;
      case RevenueCatPurchaseNotConfigured():
        ref
            .read(alertProvider.notifier)
            .showWarning(message: 'settings_upgrade_coming_soon'.tr());
      case RevenueCatPurchaseFailed():
        ref
            .read(alertProvider.notifier)
            .showError(message: 'subscription_restore_error'.tr());
    }
  }

  String _subtitle() {
    final key = SubscriptionPaywallSheet.subtitleKeyFor(widget.reason);
    if (widget.reason != PaywallReason.positionLimit) return key.tr();
    final limit = SubscriptionPolicy.positionLimit(SubscriptionTier.free);
    return key.tr(namedArgs: {'limit': '${limit ?? ''}'});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final reason = widget.reason;
    final subscription = ref.watch(subscriptionProvider);
    final offerAsync = ref.watch(paywallOfferProvider);
    final offer = offerAsync.value ?? PaywallOffer.empty;
    final isPriceLoading = offerAsync.isLoading;
    final annualEnabled =
        ref.watch(paywallAnnualEnabledProvider).value ?? false;
    final isPurchasing = subscription.isPurchasing;
    final visibleTiers = SubscriptionPaywallSheet.visibleTiersFor(
      reason,
      subscription.tier,
    );
    final showPeriods = annualEnabled && offer.hasAnnualFor(visibleTiers);
    final period = showPeriods ? _period : BillingPeriod.monthly;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      canPop: !isPurchasing,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            0,
            AppDimens.pageHorizontal,
            AppDimens.sp16 + bottomInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // La manija la pone el tema (`showDragHandle`): acá no va otra.
              Row(
                children: [
                  const Spacer(),
                  IconButton(
                    onPressed:
                        isPurchasing ? null : () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: colors.textSecondary,
                    ),
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                  ),
                ],
              ),
              Text(
                SubscriptionPaywallSheet.titleKeyFor(reason).tr(),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.02,
                ),
              ),
              const SizedBox(height: AppDimens.sp8),
              Text(
                _subtitle(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  height: 1.45,
                ),
              ),
              if (widget.preview != null) ...[
                const SizedBox(height: AppDimens.sp16),
                widget.preview!(context),
              ],
              // El medidor solo cuando el motivo es la cuota: en el resto
              // distrae de lo que el usuario vino a desbloquear.
              if (reason == PaywallReason.quotaExceeded) ...[
                const SizedBox(height: AppDimens.sp16),
                _PaywallUsageMeter(
                  used: subscription.queriesUsed,
                  limit: subscription.queriesLimit,
                ),
              ],
              // Solo tiene sentido avisarlo si una consulta de noticias pesa
              // más que una común (hoy pesan igual — ver AiUsageLimits).
              if (reason == PaywallReason.goldRequired &&
                  AiUsageLimits.newsQueryWeight >
                      AiUsageLimits.standardQueryWeight) ...[
                const SizedBox(height: AppDimens.sp12),
                Text(
                  'paywall_news_weight_note'.tr(
                    args: ['${AiUsageLimits.newsQueryWeight}'],
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: AppDimens.sectionGap),
              if (showPeriods) ...[
                SegmentedChoice<BillingPeriod>(
                  options: [
                    (
                      value: BillingPeriod.monthly,
                      label: 'paywall_period_monthly'.tr(),
                    ),
                    (
                      value: BillingPeriod.annual,
                      label: 'paywall_period_annual'.tr(),
                    ),
                  ],
                  selected: _period,
                  onChanged: (value) {
                    if (!isPurchasing) setState(() => _period = value);
                  },
                ),
                const SizedBox(height: AppDimens.sp16),
              ],
              for (var i = 0; i < visibleTiers.length; i++) ...[
                if (i > 0) const SizedBox(height: AppDimens.sp12),
                _PaywallPlanCard(
                  tier: visibleTiers[i],
                  period: period,
                  featured: visibleTiers[i] == SubscriptionTier.gold,
                  showRecommendedBadge:
                      visibleTiers.length > 1 &&
                      visibleTiers[i] == SubscriptionTier.gold,
                  price: offer.priceOf(visibleTiers[i], period),
                  savingsPercent:
                      period == BillingPeriod.annual
                          ? offer.annualSavingsPercent(visibleTiers[i])
                          : null,
                  isPriceLoading: isPriceLoading,
                  loading: subscription.purchasingTier == visibleTiers[i],
                  onSelect:
                      isPurchasing
                          ? null
                          : () => _purchase(visibleTiers[i], period),
                ),
              ],
              const SizedBox(height: AppDimens.sp16),
              const _PaywallTerms(),
              const SizedBox(height: AppDimens.sp4),
              Center(
                child: TextButton(
                  onPressed: isPurchasing ? null : _restore,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.accentBlue,
                  ),
                  child: LoadingButtonContent(
                    loading: subscription.isRestoring,
                    spinnerColor: colors.accentBlue,
                    label: Text('settings_restore_purchases'.tr()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lo que Apple (3.1.2) pide junto al botón de compra: cómo se cobra, cómo
/// se renueva y cómo se cancela, y los links a Términos y Privacidad.
/// Siempre visible, aunque falte el precio.
class _PaywallTerms extends StatelessWidget {
  const _PaywallTerms();

  static String storeName(TargetPlatform platform) => switch (platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => 'App Store',
    _ => 'Google Play',
  };

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // Sin navegador: no hay nada que mostrar.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final small = Theme.of(context).textTheme.bodySmall;
    final linkStyle = TextButton.styleFrom(
      foregroundColor: colors.textPrimary,
      minimumSize: const Size(AppDimens.touchTarget, 48),
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.sp12),
      textStyle: small?.copyWith(fontWeight: FontWeight.w600),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'paywall_terms_block'.tr(
            namedArgs: {'store': storeName(Theme.of(context).platform)},
          ),
          style: small?.copyWith(color: colors.textSecondary, height: 1.45),
        ),
        const SizedBox(height: AppDimens.sp4),
        // Wrap y no Row: con letra grande los dos links bajan de línea en
        // vez de desbordar.
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: () => _open(LegalLinks.terms),
              style: linkStyle,
              child: Text('paywall_terms_link'.tr()),
            ),
            ExcludeSemantics(
              child: Text(
                '·',
                style: small?.copyWith(color: colors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => _open(LegalLinks.privacy),
              style: linkStyle,
              child: Text('paywall_privacy_link'.tr()),
            ),
          ],
        ),
      ],
    );
  }
}

class _PaywallUsageMeter extends StatelessWidget {
  const _PaywallUsageMeter({required this.used, required this.limit});

  final int used;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final progress = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final isNearLimit = progress >= 0.85;
    final usageLabel = 'paywall_usage'.tr(
      namedArgs: {'used': '$used', 'limit': '$limit'},
    );
    final percentLabel = '${(progress * 100).round()}%';

    return Semantics(
      label: usageLabel,
      value: percentLabel,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    usageLabel,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  percentLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: isNearLimit ? colors.loss : colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.sp8),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppDimens.radiusSm),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: colors.surfaceElevated,
                color: isNearLimit ? colors.loss : colors.accentBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaywallPlanCard extends StatelessWidget {
  const _PaywallPlanCard({
    required this.tier,
    required this.period,
    required this.featured,
    required this.showRecommendedBadge,
    required this.onSelect,
    this.price,
    this.savingsPercent,
    this.isPriceLoading = false,
    this.loading = false,
  });

  final SubscriptionTier tier;
  final BillingPeriod period;
  final bool featured;
  final bool showRecommendedBadge;
  final VoidCallback? onSelect;
  final TierPrice? price;

  /// "Ahorrás N % frente al mensual" (solo en anual y con los dos precios).
  final int? savingsPercent;
  final bool isPriceLoading;
  final bool loading;

  String get _titleKey => switch (tier) {
    SubscriptionTier.premium => 'paywall_premium_title',
    SubscriptionTier.gold => 'paywall_gold_title',
    SubscriptionTier.free => '',
  };

  String get _buttonKey => switch (tier) {
    SubscriptionTier.premium => 'paywall_upgrade_premium',
    SubscriptionTier.gold => 'paywall_upgrade_gold',
    SubscriptionTier.free => '',
  };

  static List<String> _featureKeysFor(SubscriptionTier tier) =>
      SubscriptionPaywallSheet.featureKeysFor(tier);

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final features = _featureKeysFor(tier);
    final secondary =
        featured ? Colors.white.withValues(alpha: 0.72) : colors.textSecondary;
    final small = Theme.of(context).textTheme.bodySmall;
    final price = this.price;

    return Semantics(
      container: true,
      label: _titleKey.tr(),
      child: Material(
        color:
            featured
                ? SubscriptionGoldTheme.surfaceFor(Theme.of(context).brightness)
                : colors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          side: BorderSide(
            color:
                featured
                    ? SubscriptionGoldTheme.accent.withValues(alpha: 0.55)
                    : colors.border,
            width: featured ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppDimens.sp8,
                runSpacing: AppDimens.sp8,
                children: [
                  Text(
                    _titleKey.tr(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: featured ? Colors.white : colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (showRecommendedBadge)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.sp8,
                        vertical: AppDimens.sp2,
                      ),
                      decoration: BoxDecoration(
                        gradient: SubscriptionGoldTheme.badgeGradient,
                        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
                      ),
                      child: Text(
                        'paywall_recommended'.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: SubscriptionGoldTheme.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  // Porty en el color del plan: dorado en el destacado.
                  PortyAvatar(
                    size: 28,
                    palette:
                        featured
                            ? const PortyAvatarPalette(
                              body: SubscriptionGoldTheme.accent,
                              features: SubscriptionGoldTheme.ink,
                            )
                            : PortyAvatarPalette.brand,
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.sp6),
              // El skeleton del precio sigue las reglas de todos los
              // loaders: aparece si tarda más de 300 ms y dura al menos 400.
              DelayedLoaderVisibility(
                loading: isPriceLoading,
                builder:
                    (context, showSkeleton) =>
                        isPriceLoading && !showSkeleton
                            ? const SizedBox(height: _PaywallPriceLine.height)
                            : _PaywallPriceLine(
                              featured: featured,
                              priceLabel: price?.priceString,
                              period: period,
                              isLoading: showSkeleton,
                            ),
              ),
              if (savingsPercent != null && price != null) ...[
                const SizedBox(height: AppDimens.sp2),
                Text(
                  'paywall_annual_savings'.tr(
                    namedArgs: {'percent': '$savingsPercent'},
                  ),
                  style: small?.copyWith(
                    color: secondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              if (features.isNotEmpty) ...[
                const SizedBox(height: AppDimens.sp12),
                for (final featureKey in features) ...[
                  _PaywallFeatureRow(
                    label: featureKey.tr(),
                    featured: featured,
                  ),
                  if (featureKey != features.last)
                    const SizedBox(height: AppDimens.sp8),
                ],
              ],
              const SizedBox(height: AppDimens.sp12),
              Text(
                'paywall_fair_use'.tr(
                  namedArgs: {'count': '${tier.monthlyQuota}'},
                ),
                style: small?.copyWith(
                  color: secondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: AppDimens.sp16),
              if (featured)
                _GoldPlanButton(
                  label: _buttonKey.tr(),
                  loading: loading,
                  onPressed: onSelect,
                )
              else
                PositionPrimaryButton(
                  label: _buttonKey.tr(),
                  loading: loading,
                  onPressed: onSelect,
                ),
              if (price != null) ...[
                const SizedBox(height: AppDimens.sp8),
                Text(
                  'paywall_renews_line'.tr(
                    namedArgs: {
                      'period':
                          (period == BillingPeriod.annual
                                  ? 'paywall_period_year'
                                  : 'paywall_period_month')
                              .tr(),
                      'price': price.priceString,
                    },
                  ),
                  textAlign: TextAlign.center,
                  style: small?.copyWith(
                    color: secondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PaywallPriceLine extends StatelessWidget {
  /// Alto de la línea mientras el precio no está (skeleton o espera).
  static const height = 20.0;

  const _PaywallPriceLine({
    required this.featured,
    required this.priceLabel,
    required this.period,
    required this.isLoading,
  });

  final bool featured;
  final String? priceLabel;
  final BillingPeriod period;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    final String text;
    final TextStyle style;

    if (isLoading) {
      // La hoja no espera a RevenueCat: el precio aparece en su lugar.
      return Semantics(
        label: 'paywall_price_loading'.tr(),
        child: SizedBox(
          width: 96,
          height: height,
          child: Align(
            alignment: Alignment.centerLeft,
            child: QaSkeleton(lines: 1, widths: const [1]),
          ),
        ),
      );
    } else if (priceLabel != null) {
      text = (period == BillingPeriod.annual
              ? 'paywall_price_per_year'
              : 'paywall_price_per_month')
          .tr(namedArgs: {'price': priceLabel!});
      style = Theme.of(context).textTheme.titleSmall!.copyWith(
        color: featured ? Colors.white : colors.textPrimary,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
    } else {
      text = 'paywall_price_unavailable'.tr();
      style = Theme.of(context).textTheme.bodySmall!.copyWith(
        color:
            featured
                ? Colors.white.withValues(alpha: 0.72)
                : colors.textSecondary,
      );
    }

    return Text(text, style: style);
  }
}

class _PaywallFeatureRow extends StatelessWidget {
  const _PaywallFeatureRow({required this.label, required this.featured});

  final String label;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_rounded,
          size: AppDimens.iconSm,
          color:
              featured ? SubscriptionGoldTheme.accentLight : colors.accentBlue,
        ),
        const SizedBox(width: AppDimens.sp8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color:
                  featured
                      ? Colors.white.withValues(alpha: 0.88)
                      : colors.textPrimary,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _GoldPlanButton extends StatelessWidget {
  const _GoldPlanButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: LoadingButtonContent(
        loading: loading,
        spinnerColor: SubscriptionGoldTheme.ink,
        label: Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: SubscriptionGoldTheme.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        builder:
            (context, showSpinner, child) => FilledButton(
              onPressed:
                  showSpinner || onPressed == null
                      ? null
                      : loading
                      ? () {}
                      : onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: SubscriptionGoldTheme.accent,
                foregroundColor: SubscriptionGoldTheme.ink,
                disabledBackgroundColor: SubscriptionGoldTheme.accent
                    .withValues(alpha: 0.45),
                disabledForegroundColor: SubscriptionGoldTheme.ink.withValues(
                  alpha: 0.6,
                ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                ),
              ),
              child: child,
            ),
      ),
    );
  }
}
