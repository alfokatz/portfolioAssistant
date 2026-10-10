import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';

/// Starter-prompt row shown on the empty state. Flat surface, no heavy
/// outline — a quiet invitation to tap rather than a form control.
class AssistantSuggestionChip extends StatelessWidget {
  const AssistantSuggestionChip({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final enabled = onTap != null;

    return Material(
      color: colors.surfaceElevated,
      borderRadius: BorderRadius.circular(AppDimens.radiusXl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.sp16,
              vertical: 13,
            ),
            child: Row(
              children: [
                PortySpark(size: 12, color: colors.accentWarm),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
