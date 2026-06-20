import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_feature_row.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_mockup_widgets.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_entrance.dart';

class OnboardingDashboardPage extends StatelessWidget {
  const OnboardingDashboardPage({super.key, required this.activePage});

  static const pageIndex = 1;

  final int activePage;

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
              'onboarding_dashboard_title'.tr(),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.02,
                  ),
            ),
            const SizedBox(height: AppDimens.sp8),
            Text(
              'onboarding_dashboard_subtitle'.tr(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    height: 1.45,
                  ),
            ),
            const SizedBox(height: AppDimens.sp20),
            const OnboardingDashboardPreview(),
            const SizedBox(height: AppDimens.sectionGap),
            OnboardingFeatureRow(
              icon: Icons.add_box_outlined,
              title: 'onboarding_dashboard_feature_add_title'.tr(),
              subtitle: 'onboarding_dashboard_feature_add_subtitle'.tr(),
            ),
            const SizedBox(height: AppDimens.sp16),
            OnboardingFeatureRow(
              icon: Icons.archive_outlined,
              title: 'onboarding_dashboard_feature_close_title'.tr(),
              subtitle: 'onboarding_dashboard_feature_close_subtitle'.tr(),
            ),
            const SizedBox(height: AppDimens.sp16),
            OnboardingFeatureRow(
              icon: Icons.refresh_rounded,
              title: 'onboarding_dashboard_feature_refresh_title'.tr(),
              subtitle: 'onboarding_dashboard_feature_refresh_subtitle'.tr(),
            ),
          ],
        ),
      ),
    );
  }
}
