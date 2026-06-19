import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

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
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PortfolioColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SubscriptionPaywallSheet(
        reason: reason,
        onUpgraded: onUpgraded,
      ),
    );
  }

  String get _titleKey => switch (reason) {
        PaywallReason.modeLocked => 'paywall_title_mode_locked',
        PaywallReason.newsRequiresGold => 'paywall_title_news',
        PaywallReason.quotaExceeded => 'paywall_title_quota',
      };

  Future<void> _purchase(
    BuildContext context,
    WidgetRef ref,
    SubscriptionTier tier,
  ) async {
    final result =
        await ref.read(subscriptionProvider.notifier).purchaseTier(tier);
    if (!context.mounted) return;

    switch (result) {
      case RevenueCatPurchaseSuccess():
        ref.read(alertProvider.notifier).showSuccess(
              message: 'subscription_purchase_success'.tr(),
            );
        Navigator.of(context).pop();
        onUpgraded?.call();
      case RevenueCatPurchaseCancelled():
        break;
      case RevenueCatPurchaseNotConfigured():
        ref.read(alertProvider.notifier).showWarning(
              message: 'settings_upgrade_coming_soon'.tr(),
            );
      case RevenueCatPurchaseFailed():
        ref.read(alertProvider.notifier).showError(
              message: 'subscription_purchase_error'.tr(),
            );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscription = ref.watch(subscriptionProvider);
    final isPurchasing = subscription.isPurchasing;
    final usageText = 'paywall_usage'.tr(
      namedArgs: {
        'used': '${subscription.queriesUsed}',
        'limit': '${subscription.queriesLimit}',
      },
    );
    final stackPlans = MediaQuery.sizeOf(context).width < 420;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: PortfolioColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _titleKey.tr(),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: PortfolioColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              usageText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: PortfolioColors.textSecondary,
                  ),
            ),
            if (reason == PaywallReason.newsRequiresGold) ...[
              const SizedBox(height: 8),
              Text(
                'paywall_news_weight_note'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: PortfolioColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ],
            const SizedBox(height: 20),
            if (stackPlans)
              Column(
                children: [
                  _PlanCard(
                    title: 'paywall_premium_title'.tr(),
                    description: 'paywall_premium_desc'.tr(),
                    buttonLabel: 'paywall_upgrade_premium'.tr(),
                    loading: isPurchasing,
                    onUpgrade: isPurchasing
                        ? null
                        : () => _purchase(
                              context,
                              ref,
                              SubscriptionTier.premium,
                            ),
                  ),
                  const SizedBox(height: 12),
                  _PlanCard(
                    title: 'paywall_gold_title'.tr(),
                    description: 'paywall_gold_desc'.tr(),
                    buttonLabel: 'paywall_upgrade_gold'.tr(),
                    highlighted: true,
                    loading: isPurchasing,
                    onUpgrade: isPurchasing
                        ? null
                        : () => _purchase(
                              context,
                              ref,
                              SubscriptionTier.gold,
                            ),
                  ),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _PlanCard(
                      title: 'paywall_premium_title'.tr(),
                      description: 'paywall_premium_desc'.tr(),
                      buttonLabel: 'paywall_upgrade_premium'.tr(),
                      loading: isPurchasing,
                      onUpgrade: isPurchasing
                          ? null
                          : () => _purchase(
                                context,
                                ref,
                                SubscriptionTier.premium,
                              ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PlanCard(
                      title: 'paywall_gold_title'.tr(),
                      description: 'paywall_gold_desc'.tr(),
                      buttonLabel: 'paywall_upgrade_gold'.tr(),
                      highlighted: true,
                      loading: isPurchasing,
                      onUpgrade: isPurchasing
                          ? null
                          : () => _purchase(
                                context,
                                ref,
                                SubscriptionTier.gold,
                              ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: isPurchasing
                  ? null
                  : () async {
                      final result = await ref
                          .read(subscriptionProvider.notifier)
                          .restorePurchases();
                      if (!context.mounted) return;
                      switch (result) {
                        case RevenueCatPurchaseSuccess():
                          ref.read(alertProvider.notifier).showSuccess(
                                message: 'subscription_restore_success'.tr(),
                              );
                        case RevenueCatPurchaseCancelled():
                          break;
                        case RevenueCatPurchaseNotConfigured():
                          ref.read(alertProvider.notifier).showWarning(
                                message: 'settings_upgrade_coming_soon'.tr(),
                              );
                        case RevenueCatPurchaseFailed():
                          ref.read(alertProvider.notifier).showError(
                                message: 'subscription_restore_error'.tr(),
                              );
                      }
                    },
              child: Text('settings_restore_purchases'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onUpgrade,
    this.highlighted = false,
    this.loading = false,
  });

  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback? onUpgrade;
  final bool highlighted;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PortfolioColors.surfaceCard,
            PortfolioColors.surfaceElevated.withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? PortfolioColors.accentBlue : PortfolioColors.border,
          width: highlighted ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: PortfolioColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (highlighted) ...[
                const Spacer(),
                const Icon(
                  Icons.auto_awesome,
                  color: PortfolioColors.accentBlue,
                  size: 18,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PortfolioColors.textSecondary,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: highlighted
                      ? const [Color(0xFF2563EB), Color(0xFF06B6D4)]
                      : [
                          PortfolioColors.surfaceElevated,
                          PortfolioColors.surfaceElevated,
                        ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: highlighted
                    ? null
                    : Border.all(color: PortfolioColors.border),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onUpgrade,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              buttonLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    color: PortfolioColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
