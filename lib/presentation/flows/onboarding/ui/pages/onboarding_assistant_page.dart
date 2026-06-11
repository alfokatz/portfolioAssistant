import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_feature_row.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_entrance.dart';

class OnboardingAssistantPage extends StatelessWidget {
  const OnboardingAssistantPage({super.key, required this.activePage});

  static const pageIndex = 2;

  final int activePage;

  static const _modes = [
    ('assistant_mode_portfolio', Icons.pie_chart_outline_rounded,
        'onboarding_assistant_mode_portfolio_desc'),
    ('assistant_mode_learn', Icons.school_outlined,
        'onboarding_assistant_mode_learn_desc'),
    ('assistant_mode_explore', Icons.explore_outlined,
        'onboarding_assistant_mode_explore_desc'),
    ('assistant_mode_invest', Icons.bolt_outlined,
        'onboarding_assistant_mode_invest_desc'),
    ('assistant_mode_plan', Icons.track_changes_outlined,
        'onboarding_assistant_mode_plan_desc'),
  ];

  @override
  Widget build(BuildContext context) {
    return OnboardingPageEntrance(
      pageIndex: pageIndex,
      activePage: activePage,
      child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'onboarding_assistant_title'.tr(),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: PortfolioColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'onboarding_assistant_subtitle'.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: PortfolioColors.textSecondary,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 20),
          const _AssistantChatMockup(),
          const SizedBox(height: 20),
          for (var i = 0; i < _modes.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            OnboardingFeatureRow(
              icon: _modes[i].$2,
              title: _modes[i].$1.tr(),
              subtitle: _modes[i].$3.tr(),
            ),
          ],
        ],
      ),
    ),
    );
  }
}

class _AssistantChatMockup extends StatelessWidget {
  const _AssistantChatMockup();

  static const _chipKeys = [
    'assistant_mode_portfolio',
    'assistant_mode_learn',
    'assistant_mode_explore',
    'assistant_mode_invest',
    'assistant_mode_plan',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PortfolioColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PortfolioColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'portfolio_qa_title'.tr(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: PortfolioColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _chipKeys.map((key) {
                final selected = key == 'assistant_mode_portfolio';
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected
                          ? PortfolioColors.accentBlue
                          : PortfolioColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? PortfolioColors.accentBlue
                            : PortfolioColors.border,
                      ),
                    ),
                    child: Text(
                      key.tr(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? PortfolioColors.textPrimary
                            : PortfolioColors.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: PortfolioColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'portfolio_qa_disclaimer'.tr(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: PortfolioColors.textSecondary,
                    height: 1.3,
                  ),
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: PortfolioColors.accentBlue.withValues(alpha: 0.2),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
              ),
              child: Text(
                'portfolio_qa_chip_today'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: PortfolioColors.textPrimary,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: PortfolioColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PortfolioColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'onboarding_assistant_mock_response'.tr(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: PortfolioColors.textPrimary,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _MetricChip(
                      label: 'P&L',
                      value: '+2.4%',
                      color: colors.pnlColor(1),
                    ),
                    const SizedBox(width: 8),
                    _MetricChip(
                      label: 'NVDA',
                      value: '+4.5%',
                      color: colors.pnlColor(1),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: PortfolioColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PortfolioColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: PortfolioColors.textSecondary,
                ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
