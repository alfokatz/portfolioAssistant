import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_feature_row.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_mockup_widgets.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_entrance.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_header.dart';

/// Porty: una conversación de ejemplo y lo que se le puede preguntar, con
/// el plan que incluye cada cosa (sin prometer de más).
class OnboardingAssistantPage extends StatelessWidget {
  const OnboardingAssistantPage({super.key, required this.activePage});

  static const pageIndex = 2;

  final int activePage;

  @override
  Widget build(BuildContext context) {
    Widget enter(int i, Widget child) => OnboardingStaggeredEntrance(
      pageIndex: pageIndex,
      activePage: activePage,
      itemIndex: i,
      child: child,
    );

    return OnboardingPageEntrance(
      pageIndex: pageIndex,
      activePage: activePage,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          AppDimens.sp8,
          AppDimens.pageHorizontal,
          AppDimens.sp24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            enter(
              0,
              OnboardingPageHeader(
                title: 'onboarding_assistant_title'.tr(),
                subtitle: 'onboarding_assistant_subtitle'.tr(),
              ),
            ),
            const SizedBox(height: AppDimens.sp24),
            enter(1, const OnboardingChatPreview()),
            const SizedBox(height: AppDimens.sp32),
            enter(
              2,
              OnboardingFeatureRow(
                icon: Icons.pie_chart_outline_rounded,
                title: 'onboarding_assistant_feature_portfolio_title'.tr(),
                subtitle:
                    'onboarding_assistant_feature_portfolio_subtitle'.tr(),
              ),
            ),
            const SizedBox(height: AppDimens.sp20),
            enter(
              3,
              OnboardingFeatureRow(
                icon: Icons.show_chart_rounded,
                title: 'onboarding_assistant_feature_market_title'.tr(),
                subtitle: 'onboarding_assistant_feature_market_subtitle'.tr(),
                tag: 'onboarding_tag_premium'.tr(),
              ),
            ),
            const SizedBox(height: AppDimens.sp20),
            enter(
              4,
              OnboardingFeatureRow(
                icon: Icons.article_outlined,
                title: 'onboarding_assistant_feature_analysis_title'.tr(),
                subtitle:
                    'onboarding_assistant_feature_analysis_subtitle'.tr(),
                tag: 'onboarding_tag_gold'.tr(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
