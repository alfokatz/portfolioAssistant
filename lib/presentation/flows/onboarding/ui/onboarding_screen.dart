import 'package:animate_do/animate_do.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_router.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_primary_button.dart';
import 'package:portfolio_assistant/presentation/flows/home/nav/home_router.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/providers/onboarding_provider.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/pages/onboarding_assistant_page.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/pages/onboarding_dashboard_page.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/pages/onboarding_get_started_page.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/pages/onboarding_welcome_page.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_dots.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_router.dart';

class OnboardingScreen extends StatefulHookConsumerWidget {
  const OnboardingScreen({super.key});

  static const pageCount = 4;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends BaseStatefulWidget<OnboardingScreen> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    _pageController = PageController();
    super.initState();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isLastPage => _currentPage == OnboardingScreen.pageCount - 1;

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
  }

  void _goNext() {
    if (_isLastPage) {
      _finish(OnboardingExit.home);
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish(OnboardingExit exit) async {
    await ref.read(onboardingProvider).markComplete();
    if (!mounted) return;

    switch (exit) {
      case OnboardingExit.home:
        context.goNamed(HomeRouter.homeRouteName);
      case OnboardingExit.addPosition:
        context.goNamed(HomeRouter.homeRouteName);
        if (!mounted) return;
        context.pushNamed(PositionRouter.addRouteName);
      case OnboardingExit.assistant:
        context.goNamed(HomeRouter.homeRouteName);
        if (!mounted) return;
        context.pushNamed(AssistantRouter.routeName);
    }
  }

  @override
  Widget buildView(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: PortfolioColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              child: Row(
                children: [
                  if (_currentPage == 0)
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: PortfolioColors.accentBlue.withValues(alpha: 0.9),
                      size: 22,
                    )
                  else
                    const SizedBox(width: 22),
                  const Spacer(),
                  if (!_isLastPage)
                    TextButton(
                      onPressed: () => _finish(OnboardingExit.home),
                      child: Text(
                        'onboarding_skip'.tr(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: PortfolioColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                physics: const BouncingScrollPhysics(),
                children: [
                  OnboardingWelcomePage(activePage: _currentPage),
                  OnboardingDashboardPage(activePage: _currentPage),
                  OnboardingAssistantPage(activePage: _currentPage),
                  OnboardingGetStartedPage(
                    activePage: _currentPage,
                    onExit: _finish,
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 12 + bottomPadding),
              child: Column(
                children: [
                  FadeIn(
                    key: ValueKey('onboarding-footer-$_currentPage'),
                    duration: const Duration(milliseconds: 350),
                    child: OnboardingPageDots(
                      pageCount: OnboardingScreen.pageCount,
                      currentPage: _currentPage,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FadeInUp(
                    key: ValueKey('onboarding-cta-$_currentPage'),
                    duration: const Duration(milliseconds: 400),
                    from: 12,
                    child: AuthPrimaryButton(
                      label: _isLastPage
                          ? 'onboarding_start'.tr()
                          : 'onboarding_next'.tr(),
                      onPressed: _goNext,
                    ),
                  ),
                  if (_isLastPage) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => _finish(OnboardingExit.home),
                      child: Text(
                        'onboarding_skip_for_now'.tr(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: PortfolioColors.textSecondary,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
