import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_gold_theme.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';

class SubscriptionPaywallSheet extends ConsumerWidget {
  const SubscriptionPaywallSheet({
    super.key,
    required this.reason,
    this.onUpgraded,
  });

  final PaywallReason reason;
  final VoidCallback? onUpgraded;

  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required PaywallReason reason,
    VoidCallback? onUpgraded,
  }) {
    final subscription = ref.read(subscriptionProvider);
    if (subscription.tier == SubscriptionTier.gold && !subscription.isLoading) {
      return Future.value();
    }

    ref.invalidate(subscriptionTierPricesProvider);

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
          (_) =>
              SubscriptionPaywallSheet(reason: reason, onUpgraded: onUpgraded),
    );
  }

  String get _titleKey => switch (reason) {
    PaywallReason.modeLocked => 'paywall_title_mode_locked',
    PaywallReason.newsRequiresGold => 'paywall_title_news',
    PaywallReason.quotaExceeded => 'paywall_title_quota',
  };

  String get _subtitleKey => switch (reason) {
    PaywallReason.modeLocked => 'paywall_subtitle_mode_locked',
    PaywallReason.newsRequiresGold => 'paywall_subtitle_news',
    PaywallReason.quotaExceeded => 'paywall_subtitle_quota',
  };

  List<SubscriptionTier> _visibleTiers(SubscriptionTier currentTier) {
    return switch (reason) {
      PaywallReason.newsRequiresGold => [SubscriptionTier.gold],
      PaywallReason.quotaExceeded || PaywallReason.modeLocked =>
        currentTier == SubscriptionTier.premium
            ? [SubscriptionTier.gold]
            : [SubscriptionTier.gold, SubscriptionTier.premium],
    };
  }

  Future<void> _purchase(
    BuildContext context,
    WidgetRef ref,
    SubscriptionTier tier,
  ) async {
    final result = await ref
        .read(subscriptionProvider.notifier)
        .purchaseTier(tier);
    if (!context.mounted) return;

    switch (result) {
      case RevenueCatPurchaseSuccess():
        ref
            .read(alertProvider.notifier)
            .showSuccess(message: 'subscription_purchase_success'.tr());
        Navigator.of(context).pop();
        onUpgraded?.call();
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

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final result =
        await ref.read(subscriptionProvider.notifier).restorePurchases();
    if (!context.mounted) return;

    switch (result) {
      case RevenueCatPurchaseSuccess():
        ref
            .read(alertProvider.notifier)
            .showSuccess(message: 'subscription_restore_success'.tr());
        Navigator.of(context).pop();
        onUpgraded?.call();
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final subscription = ref.watch(subscriptionProvider);
    final pricesAsync = ref.watch(subscriptionTierPricesProvider);
    final tierPrices = pricesAsync.value ?? {};
    final isPriceLoading = pricesAsync.isLoading;
    final isPurchasing = subscription.isPurchasing;
    final visibleTiers = _visibleTiers(subscription.tier);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      canPop: !isPurchasing,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            AppDimens.sp12,
            AppDimens.pageHorizontal,
            AppDimens.sp16 + bottomInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
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
                _titleKey.tr(),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.02,
                ),
              ),
              const SizedBox(height: AppDimens.sp8),
              Text(
                _subtitleKey.tr(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppDimens.sp16),
              _PaywallUsageMeter(
                used: subscription.queriesUsed,
                limit: subscription.queriesLimit,
              ),
              if (reason == PaywallReason.newsRequiresGold) ...[
                const SizedBox(height: AppDimens.sp12),
                Text(
                  'paywall_news_weight_note'.tr(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: AppDimens.sectionGap),
              for (var i = 0; i < visibleTiers.length; i++) ...[
                if (i > 0) const SizedBox(height: AppDimens.sp12),
                _PaywallPlanCard(
                  tier: visibleTiers[i],
                  featured: visibleTiers[i] == SubscriptionTier.gold,
                  showRecommendedBadge:
                      visibleTiers.length > 1 &&
                      visibleTiers[i] == SubscriptionTier.gold,
                  priceLabel: tierPrices[visibleTiers[i]],
                  isPriceLoading: isPriceLoading,
                  loading: subscription.purchasingTier == visibleTiers[i],
                  onSelect:
                      isPurchasing
                          ? null
                          : () => _purchase(context, ref, visibleTiers[i]),
                ),
              ],
              const SizedBox(height: AppDimens.sp12),
              Center(
                child: TextButton(
                  onPressed: isPurchasing ? null : () => _restore(context, ref),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.accentBlue,
                  ),
                  child:
                      subscription.isRestoring
                          ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.accentBlue,
                            ),
                          )
                          : Text('settings_restore_purchases'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
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
    required this.featured,
    required this.showRecommendedBadge,
    required this.onSelect,
    this.priceLabel,
    this.isPriceLoading = false,
    this.loading = false,
  });

  final SubscriptionTier tier;
  final bool featured;
  final bool showRecommendedBadge;
  final VoidCallback? onSelect;
  final String? priceLabel;
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

  static List<String> _featureKeysFor(SubscriptionTier tier) => switch (tier) {
    SubscriptionTier.premium => const [
      'paywall_premium_feature_explore',
      'paywall_premium_feature_benchmark',
      'paywall_premium_feature_alerts',
    ],
    SubscriptionTier.gold => const [
      'paywall_gold_feature_invest',
      'paywall_gold_feature_plan',
      'paywall_gold_feature_news',
    ],
    SubscriptionTier.free => const [],
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final features = _featureKeysFor(tier);

    return Semantics(
      container: true,
      label: _titleKey.tr(),
      child: Material(
        color:
            featured ? SubscriptionGoldTheme.surfaceDark : colors.surfaceCard,
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
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: AppDimens.iconMd,
                    color:
                        featured
                            ? SubscriptionGoldTheme.accent
                            : colors.accentBlue,
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.sp6),
              Text(
                'paywall_queries_month'.tr(
                  namedArgs: {'count': '${tier.monthlyQuota}'},
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color:
                      featured
                          ? Colors.white.withValues(alpha: 0.72)
                          : colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppDimens.sp4),
              _PaywallPriceLine(
                featured: featured,
                priceLabel: priceLabel,
                isLoading: isPriceLoading,
              ),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _PaywallPriceLine extends StatelessWidget {
  const _PaywallPriceLine({
    required this.featured,
    required this.priceLabel,
    required this.isLoading,
  });

  final bool featured;
  final String? priceLabel;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    final String text;
    final TextStyle style;

    if (isLoading) {
      text = 'paywall_price_loading'.tr();
      style = Theme.of(context).textTheme.bodySmall!.copyWith(
        color:
            featured
                ? Colors.white.withValues(alpha: 0.72)
                : colors.textSecondary,
      );
    } else if (priceLabel != null) {
      text = 'paywall_price_per_month'.tr(namedArgs: {'price': priceLabel!});
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
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: SubscriptionGoldTheme.accent,
          foregroundColor: SubscriptionGoldTheme.ink,
          disabledBackgroundColor: SubscriptionGoldTheme.accent.withValues(
            alpha: 0.45,
          ),
          disabledForegroundColor: SubscriptionGoldTheme.ink.withValues(
            alpha: 0.6,
          ),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          ),
        ),
        child:
            loading
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: SubscriptionGoldTheme.ink,
                  ),
                )
                : Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: SubscriptionGoldTheme.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
      ),
    );
  }
}
