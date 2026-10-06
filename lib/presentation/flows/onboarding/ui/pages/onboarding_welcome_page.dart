import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_entrance.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_header.dart';

/// Porty se presenta: quién es y qué hace, sin datos inventados.
class OnboardingWelcomePage extends StatelessWidget {
  const OnboardingWelcomePage({super.key, required this.activePage});

  static const pageIndex = 0;

  final int activePage;

  @override
  Widget build(BuildContext context) {
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
                  OnboardingStaggeredEntrance(
                    pageIndex: pageIndex,
                    activePage: activePage,
                    itemIndex: 0,
                    child: ExcludeSemantics(
                      child: PortyAvatar(
                        size: 112,
                        animated: activePage == pageIndex,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp32),
                  OnboardingStaggeredEntrance(
                    pageIndex: pageIndex,
                    activePage: activePage,
                    itemIndex: 1,
                    child: OnboardingPageHeader(
                      title: 'onboarding_welcome_title'.tr(),
                      subtitle: 'onboarding_welcome_subtitle'.tr(),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp48),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
