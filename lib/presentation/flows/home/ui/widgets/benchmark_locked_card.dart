import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/home_chart_card.dart';

class BenchmarkLockedCard extends ConsumerWidget {
  const BenchmarkLockedCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => SubscriptionPaywallSheet.show(
          context,
          ref,
          reason: PaywallReason.modeLocked,
        ),
        borderRadius: BorderRadius.circular(16),
        child: HomeChartCard(
          title: 'benchmark_locked_title'.tr(),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: PortfolioColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.lock_outline,
                  color: PortfolioColors.textSecondary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'benchmark_locked_subtitle'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: PortfolioColors.textSecondary,
                        height: 1.3,
                      ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: PortfolioColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
