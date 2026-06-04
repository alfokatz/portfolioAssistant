import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/genui_core/models/gen_ui_flow_type.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/ai_insight_card.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/section_header.dart';

class AiInsightsSection extends StatelessWidget {
  final void Function(GenUiFlowType flowType) onInsightTap;

  const AiInsightsSection({super.key, required this.onInsightTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'ai_insights_title'.tr(),
            leading: Icon(
              Icons.auto_awesome,
              size: 20,
              color: PortfolioColors.accentBlue.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 12),
          AiInsightCard(
            icon: Icons.search,
            title: 'ai_insight_analyze_title'.tr(),
            subtitle: 'ai_insight_analyze_subtitle'.tr(),
            onTap: () => onInsightTap(GenUiFlowType.analysis),
          ),
          const SizedBox(height: 10),
          AiInsightCard(
            icon: Icons.bolt,
            title: 'ai_insight_invest_title'.tr(),
            subtitle: 'ai_insight_invest_subtitle'.tr(),
            onTap: () => onInsightTap(GenUiFlowType.invest),
          ),
          const SizedBox(height: 10),
          AiInsightCard(
            icon: Icons.track_changes,
            title: 'ai_insight_plan_title'.tr(),
            subtitle: 'ai_insight_plan_subtitle'.tr(),
            onTap: () => onInsightTap(GenUiFlowType.plan),
          ),
        ],
      ),
    );
  }
}
