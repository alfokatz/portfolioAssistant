import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

class ModeSwitchSuggestion extends StatelessWidget {
  const ModeSwitchSuggestion({
    super.key,
    required this.reasonKey,
    required this.suggestedMode,
    required this.onSwitch,
    required this.onDismiss,
  });

  final String reasonKey;
  final AssistantMode suggestedMode;
  final ValueChanged<AssistantMode> onSwitch;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('mode_suggestion_$reasonKey'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => onDismiss(),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          AppDimens.sp4,
          AppDimens.pageHorizontal,
          AppDimens.sp4,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.cardPadding,
          vertical: AppDimens.sp12,
        ),
        decoration: BoxDecoration(
          color: PortfolioColors.surfaceCard,
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          border: Border.all(color: PortfolioColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                reasonKey.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: PortfolioColors.textSecondary,
                    ),
              ),
            ),
            const SizedBox(width: AppDimens.sp8),
            TextButton(
              onPressed: () => onSwitch(suggestedMode),
              child: Text('assistant_mode_switch_button'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
