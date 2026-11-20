import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_mockup_widgets.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_entrance.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_header.dart';

/// Porty se presenta y, en vez de una lista de funciones, muestra tres
/// cosas concretas que se le pueden pedir (una por cada página que sigue).
class OnboardingWelcomePage extends StatelessWidget {
  const OnboardingWelcomePage({super.key, required this.activePage});

  static const pageIndex = 0;

  final int activePage;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    Widget enter(int i, Widget child) => OnboardingStaggeredEntrance(
      pageIndex: pageIndex,
      activePage: activePage,
      itemIndex: i,
      child: child,
    );
    final prompts = [
      'onboarding_welcome_prompt_portfolio'.tr(),
      'onboarding_welcome_prompt_goal'.tr(),
      'onboarding_welcome_prompt_alert'.tr(),
    ];

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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppDimens.sp16),
                  enter(
                    0,
                    Center(
                      child: ExcludeSemantics(
                        child: PortyAvatar(
                          size: 96,
                          animated: activePage == pageIndex,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp24),
                  enter(
                    1,
                    OnboardingPageHeader(
                      title: 'onboarding_welcome_title'.tr(),
                      subtitle: 'onboarding_welcome_subtitle'.tr(),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp32),
                  enter(
                    2,
                    Text(
                      'onboarding_welcome_prompts_label'.tr(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  for (final (i, prompt) in prompts.indexed) ...[
                    const SizedBox(height: AppDimens.sp8),
                    enter(3 + i, OnboardingExamplePrompt(text: prompt)),
                  ],
                  const SizedBox(height: AppDimens.sp32),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
