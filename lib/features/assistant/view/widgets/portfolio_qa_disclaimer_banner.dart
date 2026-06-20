import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

class PortfolioQaDisclaimerBanner extends StatelessWidget {
  const PortfolioQaDisclaimerBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final dim = PortfolioColors.textSecondary.withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        AppDimens.sp4,
        AppDimens.pageHorizontal,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 11, color: dim),
          const SizedBox(width: AppDimens.sp4),
          Expanded(
            child: Text(
              'portfolio_qa_disclaimer'.tr(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: dim,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
