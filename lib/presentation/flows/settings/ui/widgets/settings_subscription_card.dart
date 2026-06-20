import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

class SettingsSubscriptionCard extends ConsumerWidget {
  const SettingsSubscriptionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscription = ref.watch(subscriptionProvider);
    final tier = subscription.tier;
    final isGold = tier == SubscriptionTier.gold;

    final usageText = 'paywall_usage'.tr(
      namedArgs: {
        'used': '${subscription.queriesUsed}',
        'limit': '${subscription.queriesLimit}',
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isGold
                  ? [
                      const Color(0xFF1C1917),
                      const Color(0xFF292524).withValues(alpha: 0.95),
                    ]
                  : [
                      PortfolioColors.surfaceCard,
                      PortfolioColors.surfaceElevated.withValues(alpha: 0.9),
                    ],
            ),
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            border: Border.all(
              color: isGold
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
                  : PortfolioColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _PlanBadge(tier: tier),
                  const Spacer(),
                  Icon(
                    Icons.auto_awesome,
                    color: isGold
                        ? const Color(0xFFF59E0B)
                        : PortfolioColors.accentBlue,
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                usageText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: PortfolioColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                _descriptionKey(tier).tr(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: PortfolioColors.textPrimary,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: 16),
              if (isGold)
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.9),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'settings_plan_active_gold'.tr(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: PortfolioColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: Material(
                    color: PortfolioColors.accentBlue,
                    borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                    child: InkWell(
                      onTap: () => SubscriptionPaywallSheet.show(
                        context,
                        ref,
                        reason: PaywallReason.modeLocked,
                      ),
                      borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Center(
                          child: Text(
                            'settings_upgrade_plan'.tr(),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: PortfolioColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: subscription.isPurchasing
                ? null
                : () async {
                    final result = await ref
                        .read(subscriptionProvider.notifier)
                        .restorePurchases();
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
        ),
      ],
    );
  }

  String _descriptionKey(SubscriptionTier tier) => switch (tier) {
        SubscriptionTier.free => 'settings_plan_free_desc',
        SubscriptionTier.premium => 'settings_plan_premium_desc',
        SubscriptionTier.gold => 'settings_plan_gold_desc',
      };
}

class _PlanBadge extends StatelessWidget {
  const _PlanBadge({required this.tier});

  final SubscriptionTier tier;

  @override
  Widget build(BuildContext context) {
    final isGold = tier == SubscriptionTier.gold;
    final isPremium = tier == SubscriptionTier.premium;

    final labelKey = switch (tier) {
      SubscriptionTier.free => 'settings_plan_free',
      SubscriptionTier.premium => 'settings_plan_premium',
      SubscriptionTier.gold => 'settings_plan_gold',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: isGold
            ? const LinearGradient(
                colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
              )
            : null,
        color: isGold
            ? null
            : isPremium
                ? PortfolioColors.accentBlue.withValues(alpha: 0.15)
                : PortfolioColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isGold
              ? const Color(0xFFFBBF24)
              : isPremium
                  ? PortfolioColors.accentBlue.withValues(alpha: 0.5)
                  : PortfolioColors.border,
        ),
      ),
      child: Text(
        labelKey.tr(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isGold
                  ? const Color(0xFF1C1917)
                  : isPremium
                      ? PortfolioColors.accentBlue
                      : PortfolioColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
