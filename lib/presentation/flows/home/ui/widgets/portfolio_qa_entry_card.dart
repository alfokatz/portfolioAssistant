import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

class PortfolioQaEntryCard extends StatelessWidget {
  const PortfolioQaEntryCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Material(
        color: PortfolioColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimens.radiusLg),
              border: Border.all(color: PortfolioColors.border),
            ),
            padding: const EdgeInsets.all(AppDimens.cardPadding),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0x145E5CE6),
                    borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: PortfolioColors.accentBlue,
                    size: AppDimens.iconMd,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'portfolio_qa_entry_title'.tr(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: PortfolioColors.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'assistant_entry_subtitle'.tr(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: PortfolioColors.textSecondary,
                              height: 1.3,
                            ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 15,
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
