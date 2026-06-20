import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_mockup_widgets.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_entrance.dart';

class OnboardingWelcomePage extends StatelessWidget {
  const OnboardingWelcomePage({super.key, required this.activePage});

  static const pageIndex = 0;

  final int activePage;

  @override
  Widget build(BuildContext context) {
    return OnboardingPageEntrance(
      pageIndex: pageIndex,
      activePage: activePage,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const Spacer(flex: 2),
            OnboardingStaggeredEntrance(
              pageIndex: pageIndex,
              activePage: activePage,
              itemIndex: 0,
              child: const OnboardingPhoneMockup(),
            ),
            const Spacer(flex: 2),
            OnboardingStaggeredEntrance(
              pageIndex: pageIndex,
              activePage: activePage,
              itemIndex: 1,
              child: Text(
                'onboarding_welcome_title'.tr(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: PortfolioColors.textPrimary,
                    ),
              ),
            ),
            const SizedBox(height: 10),
            OnboardingStaggeredEntrance(
              pageIndex: pageIndex,
              activePage: activePage,
              itemIndex: 2,
              child: Text(
                'onboarding_welcome_subtitle'.tr(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: PortfolioColors.accentBlue,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
              ),
            ),
            const SizedBox(height: 10),
            OnboardingStaggeredEntrance(
              pageIndex: pageIndex,
              activePage: activePage,
              itemIndex: 3,
              child: Text(
                'onboarding_welcome_body'.tr(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: PortfolioColors.textSecondary,
                      height: 1.45,
                    ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
