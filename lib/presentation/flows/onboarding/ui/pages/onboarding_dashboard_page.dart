import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_feature_row.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_mockup_widgets.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_entrance.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_header.dart';

/// La cartera: cómo se ve la Home y lo que se hace con ella.
class OnboardingDashboardPage extends StatelessWidget {
  const OnboardingDashboardPage({super.key, required this.activePage});

  static const pageIndex = 1;

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
                title: 'onboarding_dashboard_title'.tr(),
                subtitle: 'onboarding_dashboard_subtitle'.tr(),
              ),
            ),
            const SizedBox(height: AppDimens.sp24),
            enter(1, const OnboardingPortfolioPreview()),
            const SizedBox(height: AppDimens.sp32),
            enter(
              2,
              OnboardingFeatureRow(
                icon: Icons.add_rounded,
                title: 'onboarding_dashboard_feature_add_title'.tr(),
                subtitle: 'onboarding_dashboard_feature_add_subtitle'.tr(),
              ),
            ),
            const SizedBox(height: AppDimens.sp20),
            enter(
              3,
              OnboardingFeatureRow(
                icon: Icons.sell_outlined,
                title: 'onboarding_dashboard_feature_close_title'.tr(),
                subtitle: 'onboarding_dashboard_feature_close_subtitle'.tr(),
              ),
            ),
            const SizedBox(height: AppDimens.sp20),
            enter(
              4,
              OnboardingFeatureRow(
                icon: Icons.touch_app_outlined,
                title: 'onboarding_dashboard_feature_history_title'.tr(),
                subtitle: 'onboarding_dashboard_feature_history_subtitle'.tr(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
