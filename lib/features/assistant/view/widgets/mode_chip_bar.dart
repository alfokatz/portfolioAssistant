import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

class ModeChipBar extends StatelessWidget {
  const ModeChipBar({
    super.key,
    required this.selectedMode,
    required this.onModeSelected,
    this.tier = SubscriptionTier.free,
    this.onLockedModeTap,
  });

  final AssistantMode selectedMode;
  final ValueChanged<AssistantMode> onModeSelected;
  final SubscriptionTier tier;
  final ValueChanged<AssistantMode>? onLockedModeTap;

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
              locked: !SubscriptionPolicy.isModeAllowed(tier, mode),
              onTap: () {
                if (!SubscriptionPolicy.isModeAllowed(tier, mode)) {
                  onLockedModeTap?.call(mode);
                } else {
                  onModeSelected(mode);
                }
              },
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
    this.locked = false,
  });

  final String label;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Material(
      color: selected ? PortfolioColors.accentBlue : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: selected
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: PortfolioColors.border),
                ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (locked) ...[
                Icon(
                  Icons.lock_outline,
                  size: 13,
                  color: selected
                      ? PortfolioColors.textPrimary
                      : PortfolioColors.textSecondary,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? PortfolioColors.textPrimary
                      : PortfolioColors.textSecondary,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!locked) return chip;

    return Opacity(
      opacity: 0.45,
      child: chip,
    );
  }
}
