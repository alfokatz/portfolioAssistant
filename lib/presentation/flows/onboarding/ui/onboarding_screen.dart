import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_router.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/features/etoro/nav/etoro_router.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/statement_import/nav/statement_import_router.dart';
import 'package:portfolio_assistant/presentation/flows/home/nav/home_router.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/providers/onboarding_provider.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/pages/onboarding_bring_portfolio_page.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/pages/onboarding_welcome_page.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_dots.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_router.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';

/// Dos pasos: quién es Porty y traer la cartera. El "aha" (el primer
/// diagnóstico) llega apenas la cartera tiene posiciones, así que el
/// onboarding no explica funciones: lleva a cargarla por el camino más
/// cómodo (ver docs/superpowers/plans/2026-10-26-aha-moment.md).
class OnboardingScreen extends StatefulHookConsumerWidget {
  const OnboardingScreen({super.key});

  static const pageCount = 2;

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
    runAfterPostFrameCallback(
      () => ref.read(productEventsProvider).log(ProductEvent.onboardingStarted),
    );
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _pageController.nextPage(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish(OnboardingExit exit) async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);
    ref.read(productEventsProvider).log(ProductEvent.onboardingFinished, {
      'exit': exit.name,
    });
    await ref.read(onboardingProvider).markComplete();
    if (!mounted) return;

    // Todas pasan por la Home: "atrás" desde la carga vuelve ahí.
    context.goNamed(HomeRouter.homeRouteName);
    if (!mounted) return;
    switch (exit) {
      case OnboardingExit.home:
        break;
      case OnboardingExit.addPosition:
        context.pushNamed(PositionRouter.addRouteName);
      case OnboardingExit.importFile:
        context.pushNamed(StatementImportRouter.routeName);
      case OnboardingExit.writeIt:
        context.pushNamed(
          StatementImportRouter.routeName,
          queryParameters: {StatementImportRouter.writeParam: '1'},
        );
      case OnboardingExit.connectEtoro:
        // La pantalla de eToro explica qué hace Porty con la cuenta antes de
        // pedir nada (y que la primera importación es gratis).
        context.pushNamed(EtoroRouter.connectionRouteName);
      case OnboardingExit.assistant:
        // Assistant es una pestaña del shell: se entra con `goNamed`.
        context.goNamed(AssistantRouter.routeName);
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
                  physics:
                      reduceMotion
                          ? const ClampingScrollPhysics()
                          : const BouncingScrollPhysics(),
                  children: [
                    OnboardingWelcomePage(activePage: _currentPage),
                    OnboardingBringPortfolioPage(
                      activePage: _currentPage,
                      enabled: !_isFinishing,
                      onChoose: _finish,
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
                  // En "Traé tu cartera" las filas son la acción: abajo
                  // queda solo "Ahora no".
                  if (!_isLastPage)
                    PositionPrimaryButton(
                      label: 'onboarding_start'.tr(),
                      onPressed: _isFinishing ? null : _goNext,
                    )
                  else
                    SizedBox(
                      height: 52,
                      child: Center(
                        child: TextButton(
                          onPressed:
                              _isFinishing
                                  ? null
                                  : () => _finish(OnboardingExit.home),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(
                              AppDimens.touchTarget,
                              AppDimens.touchTarget,
                            ),
                          ),
                          child: Text(
                            'onboarding_skip_for_now'.tr(),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colors.textSecondary),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
