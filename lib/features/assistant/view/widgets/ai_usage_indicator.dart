import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

class AiUsageIndicator extends ConsumerWidget {
  const AiUsageIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscription = ref.watch(subscriptionProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'assistant_usage_label'.tr(
            namedArgs: {
              'used': '${subscription.queriesUsed}',
              'limit': '${subscription.queriesLimit}',
            },
          ),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: PortfolioColors.textSecondary,
              ),
        ),
      ),
    );
  }
}
