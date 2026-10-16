import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/allocation/nav/allocation_router.dart';
import 'package:portfolio_assistant/features/allocation/providers/allocation_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// En la Home, solo si la cartera se alejó del plan más que el umbral:
/// "Tu cartera se alejó de tu plan · VOO 62% (objetivo 50%)". Fila plana
/// con borde, como los otros avisos; al tocarla, el plan.
class AllocationDriftBanner extends ConsumerStatefulWidget {
  const AllocationDriftBanner({super.key});

  @override
  ConsumerState<AllocationDriftBanner> createState() =>
      _AllocationDriftBannerState();
}

class _AllocationDriftBannerState extends ConsumerState<AllocationDriftBanner> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tier = ref.read(subscriptionProvider).tier;
      if (SubscriptionPolicy.allows(tier, PlanFeature.allocationPlan)) {
        ref.read(allocationProvider.notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tier = ref.watch(subscriptionProvider).tier;
    final worst = ref.watch(allocationDriftProvider);
    if (worst == null ||
        !SubscriptionPolicy.allows(tier, PlanFeature.allocationPlan)) {
      return const SizedBox.shrink();
    }
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final f = NumberFormat.decimalPatternDigits(decimalDigits: 0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sectionGap,
      ),
      child: Material(
        color: colors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.pushNamed(AllocationRouter.routeName),
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.sp16),
            child: Row(
              children: [
                Icon(
                  Icons.donut_large_rounded,
                  size: AppDimens.iconMd,
                  color: colors.accentWarm,
                ),
                const SizedBox(width: AppDimens.sp12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'allocation_banner_title'.tr(),
                        style: tt.bodyMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'allocation_banner_body'.tr(
                          namedArgs: {
                            'ticker': worst.ticker,
                            'current': f.format(worst.currentPct),
                            'target': f.format(worst.targetPct),
                          },
                        ),
                        style: tt.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
