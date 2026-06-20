import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

class AssistantModeChips extends StatelessWidget {
  const AssistantModeChips({super.key, required this.onModeTap});

  final void Function(AssistantMode mode) onModeTap;

  static const _modes = [
    (
      mode: AssistantMode.explore,
      icon: Icons.explore_outlined,
      labelKey: 'assistant_shortcut_explore_title',
    ),
    (
      mode: AssistantMode.invest,
      icon: Icons.bolt_outlined,
      labelKey: 'assistant_shortcut_invest_title',
    ),
    (
      mode: AssistantMode.plan,
      icon: Icons.track_changes_outlined,
      labelKey: 'assistant_shortcut_plan_title',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sp12,
      ),
      child: Row(
        children: [
          for (var i = 0; i < _modes.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _ModeChip(
                icon: _modes[i].icon,
                label: _modes[i].labelKey.tr(),
                onTap: () => onModeTap(_modes[i].mode),
                colors: colors,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final CustomColors colors;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: AppDimens.touchTarget,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: colors.accentBlue),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
