import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_feature_page.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_feature_row.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_goal_preview.dart';

/// Metas: se le cuenta a Porty qué se quiere lograr, Porty arma el plan y
/// la meta se sigue sola con la cartera.
class OnboardingGoalsPage extends StatelessWidget {
  const OnboardingGoalsPage({super.key, required this.activePage});

  static const pageIndex = 3;

  final int activePage;

  @override
  Widget build(BuildContext context) {
    return OnboardingFeaturePage(
      pageIndex: pageIndex,
      activePage: activePage,
      title: 'onboarding_goals_title'.tr(),
      subtitle: 'onboarding_goals_subtitle'.tr(),
      tag: 'onboarding_tag_premium'.tr(),
      showcase: const OnboardingGoalPreview(),
      features: [
        OnboardingFeatureRow(
          icon: Icons.trending_up_rounded,
          title: 'onboarding_goals_feature_track_title'.tr(),
          subtitle: 'onboarding_goals_feature_track_subtitle'.tr(),
        ),
        OnboardingFeatureRow(
          icon: Icons.science_outlined,
          title: 'onboarding_goals_feature_simulate_title'.tr(),
          subtitle: 'onboarding_goals_feature_simulate_subtitle'.tr(),
        ),
      ],
    );
  }
}
