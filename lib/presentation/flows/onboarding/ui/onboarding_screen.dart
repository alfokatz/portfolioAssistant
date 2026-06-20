import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_router.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/nav/home_router.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/providers/onboarding_provider.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/pages/onboarding_assistant_page.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/pages/onboarding_dashboard_page.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/pages/onboarding_get_started_page.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/pages/onboarding_welcome_page.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_dots.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_router.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';

class OnboardingScreen extends StatefulHookConsumerWidget {
  const OnboardingScreen({super.key});

  static const pageCount = 4;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends BaseStatefulWidget<OnboardingScreen> {
  late final PageController _pageController;
  int _currentPage = 0;
  bool _isFinishing = false;

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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _pageController.nextPage(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish(OnboardingExit exit) async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);
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
    final colors = context.customColors;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pageHorizontal,
                AppDimens.sp8,
                AppDimens.pageHorizontal,
                0,
              ),
              child: Row(
                children: [
                  if (_currentPage == 0)
                    Semantics(
                      label: 'app_name'.tr(),
                      child: ExcludeSemantics(
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          color: colors.accentBlue,
                          size: 22,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 22),
                  const Spacer(),
                  if (!_isLastPage)
                    TextButton(
                      onPressed: _isFinishing
                          ? null
                          : () => _finish(OnboardingExit.home),
                      child: Text(
                        'onboarding_skip'.tr(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Semantics(
                label: 'onboarding_page_indicator'.tr(
                  namedArgs: {
                    'current': '${_currentPage + 1}',
                    'total': '${OnboardingScreen.pageCount}',
                  },
                ),
                child: PageView(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  physics: reduceMotion
                      ? const ClampingScrollPhysics()
                      : const BouncingScrollPhysics(),
                  children: [
                    OnboardingWelcomePage(activePage: _currentPage),
                    OnboardingDashboardPage(activePage: _currentPage),
                    OnboardingAssistantPage(activePage: _currentPage),
                    OnboardingGetStartedPage(
                      activePage: _currentPage,
                      onExit: _finish,
                      isFinishing: _isFinishing,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppDimens.pageHorizontal,
                AppDimens.sp8,
                AppDimens.pageHorizontal,
                AppDimens.sp12 + bottomPadding,
              ),
              child: Column(
                children: [
                  OnboardingPageDots(
                    pageCount: OnboardingScreen.pageCount,
                    currentPage: _currentPage,
                  ),
                  const SizedBox(height: AppDimens.sp20),
                  PositionPrimaryButton(
                    label: _isLastPage
                        ? 'onboarding_start'.tr()
                        : 'onboarding_next'.tr(),
                    loading: _isFinishing,
                    onPressed: _isFinishing ? null : _goNext,
                  ),
                  if (_isLastPage) ...[
                    const SizedBox(height: AppDimens.sp12),
                    TextButton(
                      onPressed: _isFinishing
                          ? null
                          : () => _finish(OnboardingExit.home),
                      child: Text(
                        'onboarding_skip_for_now'.tr(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.textSecondary,
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
