import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

class ModeChipBar extends StatelessWidget {
  const ModeChipBar({
    super.key,
    required this.selectedMode,
    required this.onModeSelected,
  });

  final AssistantMode selectedMode;
  final ValueChanged<AssistantMode> onModeSelected;

  static const _modes = [
    (AssistantMode.portfolio, 'assistant_mode_portfolio'),
    (AssistantMode.learn, 'assistant_mode_learn'),
    (AssistantMode.explore, 'assistant_mode_explore'),
    (AssistantMode.invest, 'assistant_mode_invest'),
    (AssistantMode.plan, 'assistant_mode_plan'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final (mode, labelKey) in _modes) ...[
            _ModeChip(
              label: labelKey.tr(),
              selected: selectedMode == mode,
              onTap: () => onModeSelected(mode),
            ),
            if (mode != _modes.last.$1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PortfolioColors.accentBlue : PortfolioColors.surfaceCard,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? PortfolioColors.textPrimary
                  : PortfolioColors.textSecondary,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
