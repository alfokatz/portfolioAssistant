import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_progress.dart';
import 'package:portfolio_assistant/features/goals/view/goal_analysis.dart';
import 'package:portfolio_assistant/features/goals/view/goals_screen.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_mockup_widgets.dart';

/// Una meta de punta a punta: se la pide a Porty, Porty arma el plan y la
/// meta queda en la pestaña Metas con cómo viene y dónde invertir.
class OnboardingGoalPreview extends StatelessWidget {
  const OnboardingGoalPreview({super.key});

  static const _target = 12000.0;
  static const _saved = 3840.0;
  static const _monthly = 310.0;
  static const _allocation = [('VOO', 0.7), ('BND', 0.3)];

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final date = DateFormat.yMMMM(locale).format(DateTime(2028, 12));
    const status = GoalProgressStatus.onTrack;
    final statusColor = GoalAnalysis.statusColor(status, colors);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingUserBubble(
          text: 'onboarding_goals_question'.tr(
            namedArgs: {'amount': QaFormat.money(_target)},
          ),
        ),
        const SizedBox(height: AppDimens.sp16),
        OnboardingPortyReply(
          text: 'onboarding_goals_answer'.tr(
            namedArgs: {'monthly': QaFormat.money(_monthly), 'date': date},
          ),
        ),
        const SizedBox(height: AppDimens.sp12),
        ExcludeSemantics(
          child: OnboardingMockCard(
            padding: const EdgeInsets.all(AppDimens.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.accentBlue.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.flight_takeoff_rounded,
                        size: 20,
                        color: colors.accentBlue,
                      ),
                    ),
                    const SizedBox(width: AppDimens.sp12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'onboarding_goals_card_title'.tr(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            'goals_card_subtitle'.tr(
                              namedArgs: {
                                'amount': QaFormat.money(_target),
                                'date': date,
                              },
                            ),
                            style: tt.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppDimens.sp8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.sp8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                            AppDimens.radiusPill,
                          ),
                        ),
                        child: Text(
                          GoalAnalysis.statusLabel(status),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDimens.sp16),
                GoalProgressBar(fraction: _saved / _target, color: statusColor),
                const SizedBox(height: AppDimens.sp8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'goals_card_saved'.tr(
                          namedArgs: {
                            'saved': QaFormat.money(_saved),
                            'target': QaFormat.money(_target),
                          },
                        ),
                        style: tt.bodySmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontFeatures: onboardingTabular,
                        ),
                      ),
                    ),
                    Text(
                      'goals_card_monthly'.tr(
                        namedArgs: {'monthly': QaFormat.money(_monthly)},
                      ),
                      style: tt.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        fontFeatures: onboardingTabular,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDimens.sp16),
                Divider(height: 1, thickness: 0.5, color: colors.border),
                const SizedBox(height: AppDimens.sp12),
                Text(
                  'goal_plan_allocation'.tr(),
                  style: tt.labelMedium?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                for (final (ticker, weight) in _allocation) ...[
                  const SizedBox(height: AppDimens.sp8),
                  Row(
                    children: [
                      OnboardingTickerAvatar(ticker: ticker, size: 24),
                      const SizedBox(width: AppDimens.sp8),
                      SizedBox(
                        width: 44,
                        child: Text(
                          ticker,
                          style: tt.labelLarge?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: weight,
                            minHeight: 6,
                            color: colors.chartLine,
                            backgroundColor: colors.surfaceElevated,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppDimens.sp12),
                      Text(
                        QaFormat.pct(weight * 100, digits: 0),
                        style: tt.labelLarge?.copyWith(
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontFeatures: onboardingTabular,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
