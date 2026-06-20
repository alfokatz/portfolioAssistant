import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_feature_row.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_entrance.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/surface_card.dart';

class OnboardingAssistantPage extends StatelessWidget {
  const OnboardingAssistantPage({super.key, required this.activePage});

  static const pageIndex = 2;

  final int activePage;

  static const _modes = [
    (
      titleKey: 'assistant_shortcut_explore_title',
      icon: Icons.explore_outlined,
      descKey: 'onboarding_assistant_mode_explore_desc',
    ),
    (
      titleKey: 'assistant_shortcut_invest_title',
      icon: Icons.bolt_outlined,
      descKey: 'onboarding_assistant_mode_invest_desc',
    ),
    (
      titleKey: 'assistant_shortcut_plan_title',
      icon: Icons.track_changes_outlined,
      descKey: 'onboarding_assistant_mode_plan_desc',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return OnboardingPageEntrance(
      pageIndex: pageIndex,
      activePage: activePage,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          AppDimens.sp8,
          AppDimens.pageHorizontal,
          AppDimens.sp16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'onboarding_assistant_title'.tr(),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.02,
                  ),
            ),
            const SizedBox(height: AppDimens.sp8),
            Text(
              'onboarding_assistant_subtitle'.tr(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    height: 1.45,
                  ),
            ),
            const SizedBox(height: AppDimens.sp20),
            const _AssistantChatMockup(),
            const SizedBox(height: AppDimens.sectionGap),
            for (var i = 0; i < _modes.length; i++) ...[
              if (i > 0) const SizedBox(height: AppDimens.sp16),
              OnboardingFeatureRow(
                icon: _modes[i].icon,
                title: _modes[i].titleKey.tr(),
                subtitle: _modes[i].descKey.tr(),
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
    'assistant_shortcut_explore_title',
    'assistant_shortcut_invest_title',
    'assistant_shortcut_plan_title',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return ExcludeSemantics(
      child: SurfaceCard(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'portfolio_qa_entry_title'.tr(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: AppDimens.sp12),
          Row(
            children: [
              for (var i = 0; i < _chipKeys.length; i++) ...[
                if (i > 0) const SizedBox(width: AppDimens.sp8),
                Expanded(
                  child: Container(
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == 0
                          ? colors.surfaceElevated
                          : colors.surfaceCard,
                      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                      border: Border.all(
                        color: i == 0 ? colors.accentBlue : colors.border,
                      ),
                    ),
                    child: Text(
                      _chipKeys[i].tr(),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: i == 0
                                ? colors.textPrimary
                                : colors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppDimens.sp12),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.sp12,
                vertical: AppDimens.sp12,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppDimens.radiusLg),
                  topRight: Radius.circular(AppDimens.radiusLg),
                  bottomLeft: Radius.circular(AppDimens.radiusLg),
                ),
                border: Border.all(color: colors.border),
              ),
              child: Text(
                'portfolio_qa_chip_today'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textPrimary,
                    ),
              ),
            ),
          ),
          const SizedBox(height: AppDimens.sp12),
          Text(
            'onboarding_assistant_mock_response'.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textPrimary,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: AppDimens.sp12),
          Row(
            children: [
              _MetricChip(
                label: 'P&L',
                value: '+2.4%',
                color: colors.pnlColor(1),
              ),
              const SizedBox(width: AppDimens.sp8),
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
    final colors = context.customColors;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.sp12,
        vertical: AppDimens.sp6,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(width: AppDimens.sp6),
          Text(
            value,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}
