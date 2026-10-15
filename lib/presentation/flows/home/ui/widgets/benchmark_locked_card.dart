import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/home_chart_card.dart';

/// "Contra el mercado" para quien no tiene Premium: la misma card que la
/// comparación, con una sola fila bloqueada que abre el paywall.
class BenchmarkLockedCard extends ConsumerWidget {
  const BenchmarkLockedCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sp16,
      ),
      child: HomeChartCard(
        title: 'home_benchmark_title'.tr(),
        child: Semantics(
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppDimens.radiusMd),
            onTap: () {
              PortyHapticsService.maybeOf(context)?.lockedTap();
              SubscriptionPaywallSheet.show(
                context,
                ref,
                reason: PaywallReason.modeLocked,
                source: 'home_benchmark',
              );
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppDimens.touchTarget,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    color: colors.textSecondary,
                    size: AppDimens.iconSm + 2,
                  ),
                  const SizedBox(width: AppDimens.sp12),
                  Expanded(
                    child: Text(
                      'home_benchmark_locked'.tr(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimens.sp8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: AppDimens.iconMd,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
