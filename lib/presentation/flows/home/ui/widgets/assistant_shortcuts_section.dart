import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/ai_insight_card.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/section_header.dart';

class AssistantShortcutsSection extends StatelessWidget {
  final void Function(AssistantMode mode) onShortcutTap;

  const AssistantShortcutsSection({super.key, required this.onShortcutTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'assistant_shortcuts_title'.tr(),
            leading: Icon(
              Icons.auto_awesome,
              size: 20,
              color: PortfolioColors.accentBlue.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 12),
          AiInsightCard(
            icon: Icons.explore,
            title: 'assistant_shortcut_explore_title'.tr(),
            subtitle: 'assistant_shortcut_explore_subtitle'.tr(),
            onTap: () => onShortcutTap(AssistantMode.explore),
          ),
          const SizedBox(height: 10),
          AiInsightCard(
            icon: Icons.bolt,
            title: 'assistant_shortcut_invest_title'.tr(),
            subtitle: 'assistant_shortcut_invest_subtitle'.tr(),
            onTap: () => onShortcutTap(AssistantMode.invest),
          ),
          const SizedBox(height: 10),
          AiInsightCard(
            icon: Icons.track_changes,
            title: 'assistant_shortcut_plan_title'.tr(),
            subtitle: 'assistant_shortcut_plan_subtitle'.tr(),
            onTap: () => onShortcutTap(AssistantMode.plan),
          ),
        ],
      ),
    );
  }
}
