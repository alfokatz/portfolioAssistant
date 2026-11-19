import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/subscription/config/paywall_source.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_gold_theme.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';

class SettingsSubscriptionCard extends ConsumerWidget {
  const SettingsSubscriptionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final subscription = ref.watch(subscriptionProvider);
    final tier = subscription.tier;
    final isGold = tier == SubscriptionTier.gold;

    final limit = subscription.queriesLimit;
    final remaining = subscription.queriesRemaining.clamp(0, limit);
    final usageText = 'settings_queries_remaining'.tr(
      namedArgs: {'remaining': '$remaining', 'limit': '$limit'},
    );
    final usedShare =
        limit <= 0 ? 0.0 : ((limit - remaining) / limit).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppDimens.cardPaddingLg),
          decoration: BoxDecoration(
            color: isGold
                ? SubscriptionGoldTheme.surfaceFor(Theme.of(context).brightness)
                : colors.surfaceCard,
            gradient: isGold
                ? SubscriptionGoldTheme.cardGradientFor(
                  Theme.of(context).brightness,
                )
                : null,
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            border: Border.all(
              color: isGold
                  ? SubscriptionGoldTheme.accent.withValues(alpha: 0.5)
                  : colors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _PlanBadge(tier: tier),
                  const Spacer(),
                  PortyAvatar(
                    size: 30,
                    palette: isGold
                        ? const PortyAvatarPalette(
                            body: SubscriptionGoldTheme.accent,
                            features: SubscriptionGoldTheme.ink,
                          )
                        : PortyAvatarPalette.brand,
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.sp12),
              // Las consultas a Porty que le quedan este mes (ya no se ven
              // en el chat): el número y una barra de lo usado.
              Text(
                usageText,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isGold ? Colors.white : colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              const SizedBox(height: AppDimens.sp8),
              _UsageBar(
                share: usedShare,
                track: isGold
                    ? Colors.white.withValues(alpha: 0.18)
                    : colors.border,
                fill: isGold ? SubscriptionGoldTheme.accent : colors.accentBlue,
              ),
              const SizedBox(height: AppDimens.sp12),
              Text(
                _description(tier),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isGold ? Colors.white : colors.textPrimary,
                      height: 1.45,
                    ),
              ),
              const SizedBox(height: AppDimens.sp16),
              if (isGold)
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: SubscriptionGoldTheme.accent.withValues(alpha: 0.95),
                      size: 20,
                    ),
                    const SizedBox(width: AppDimens.sp8),
                    Expanded(
                      child: Text(
                        'settings_plan_active_gold'.tr(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () => SubscriptionPaywallSheet.show(
                      context,
                      ref,
                      reason: PaywallReason.plans,
                      source: PaywallSource.settings,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.textPrimary,
                      foregroundColor: colors.surfaceCard,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppDimens.radiusLg),
                      ),
                    ),
                    child: Text(
                      'settings_upgrade_plan'.tr(),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colors.surfaceCard,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppDimens.sp8),
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
            style: TextButton.styleFrom(
              foregroundColor: colors.accentBlue,
            ),
            child: Text('settings_restore_purchases'.tr()),
          ),
        ),
      ],
    );
  }

  /// "500 consultas/mes · Cualquier ticker… · …", desde la matriz de planes
  /// (la misma que usan el gating y el paywall).
  String _description(SubscriptionTier tier) => [
        'paywall_queries_month'.tr(
          namedArgs: {'count': '${PlanMatrix.of(tier).monthlyQueries}'},
        ),
        for (final key in PlanMatrix.marketingKeys(tier)) key.tr(),
      ].join(' · ');
}

class _PlanBadge extends StatelessWidget {
  const _PlanBadge({required this.tier});

  final SubscriptionTier tier;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
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
        gradient: isGold ? SubscriptionGoldTheme.badgeGradient : null,
        color: isGold
            ? null
            : isPremium
                ? colors.accentBlue.withValues(alpha: 0.15)
                : colors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        border: Border.all(
          color: isGold
              ? SubscriptionGoldTheme.accentLight
              : isPremium
                  ? colors.accentBlue.withValues(alpha: 0.5)
                  : colors.border,
        ),
      ),
      child: Text(
        labelKey.tr(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isGold
                  ? SubscriptionGoldTheme.surfaceDark
                  : isPremium
                      ? colors.accentBlue
                      : colors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

/// Barra fina de lo usado de la cuota del mes.
class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.share,
    required this.track,
    required this.fill,
  });

  final double share;
  final Color track;
  final Color fill;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: track)),
            FractionallySizedBox(
              widthFactor: share,
              heightFactor: 1,
              child: ColoredBox(color: fill),
            ),
          ],
        ),
      ),
    ),
  );
}
