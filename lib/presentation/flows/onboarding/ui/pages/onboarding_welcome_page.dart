import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_mockup_widgets.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_entrance.dart';

class OnboardingWelcomePage extends StatelessWidget {
  const OnboardingWelcomePage({super.key, required this.activePage});

  static const pageIndex = 0;

  final int activePage;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return OnboardingPageEntrance(
      pageIndex: pageIndex,
      activePage: activePage,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.pageHorizontal,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: AppDimens.sp24),
                  OnboardingStaggeredEntrance(
                    pageIndex: pageIndex,
                    activePage: activePage,
                    itemIndex: 0,
                    child: const OnboardingSnapshotPreview(),
                  ),
                  const SizedBox(height: AppDimens.sectionGap),
                  OnboardingStaggeredEntrance(
                    pageIndex: pageIndex,
                    activePage: activePage,
                    itemIndex: 1,
                    child: Text(
                      'onboarding_welcome_title'.tr(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.02,
                          ),
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp12),
                  OnboardingStaggeredEntrance(
                    pageIndex: pageIndex,
                    activePage: activePage,
                    itemIndex: 2,
                    child: Text(
                      'onboarding_welcome_subtitle'.tr(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp12),
                  OnboardingStaggeredEntrance(
                    pageIndex: pageIndex,
                    activePage: activePage,
                    itemIndex: 3,
                    child: Text(
                      'onboarding_welcome_body'.tr(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.textSecondary,
                            height: 1.5,
                          ),
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
