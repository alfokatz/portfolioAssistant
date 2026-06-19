import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
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
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: PortfolioColors.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: PortfolioColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                reasonKey.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: PortfolioColors.textSecondary,
                      height: 1.35,
                    ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => onSwitch(suggestedMode),
              child: Text(
                'assistant_mode_switch_button'.tr(),
                style: const TextStyle(color: PortfolioColors.accentBlue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
