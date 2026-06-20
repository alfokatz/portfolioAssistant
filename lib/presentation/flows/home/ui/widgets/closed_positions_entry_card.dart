import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

class ClosedPositionsEntryCard extends StatelessWidget {
  const ClosedPositionsEntryCard({
    super.key,
    required this.onTap,
    this.count,
  });

  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final subtitle = count != null && count! > 0
        ? 'closed_positions_entry_subtitle'.tr(namedArgs: {'count': '$count'})
        : 'closed_positions_entry_subtitle_empty'.tr();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Material(
        color: PortfolioColors.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: PortfolioColors.border),
            ),
            padding: const EdgeInsets.all(AppDimens.cardPadding),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: PortfolioColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                  ),
                  child: const Icon(
                    Icons.archive_outlined,
                    color: PortfolioColors.textSecondary,
                    size: AppDimens.iconMd,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'closed_positions_entry_title'.tr(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: PortfolioColors.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: PortfolioColors.textSecondary,
                            ),
                      ),
                    ],
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
      ),
    );
  }
}
