import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_entrance.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_header.dart';

/// El primer paso concreto: cargar la cartera (el botón de abajo, en
/// [OnboardingScreen]). Y el aviso de que Porty es información educativa.
class OnboardingGetStartedPage extends StatelessWidget {
  const OnboardingGetStartedPage({super.key, required this.activePage});

  static const pageIndex = 3;

  final int activePage;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    Widget enter(int i, Widget child) => OnboardingStaggeredEntrance(
      pageIndex: pageIndex,
      activePage: activePage,
      itemIndex: i,
      child: child,
    );

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
                  enter(
                    0,
                    ExcludeSemantics(
                      child: PortyAvatar(
                        size: 80,
                        state: PortyAvatarState.answered,
                        animated: activePage == pageIndex,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp24),
                  enter(
                    1,
                    OnboardingPageHeader(
                      title: 'onboarding_finish_title'.tr(),
                      subtitle: 'onboarding_finish_subtitle'.tr(),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp32),
                  enter(
                    2,
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: AppDimens.iconSm + 2,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: AppDimens.sp8),
                        Expanded(
                          child: Text(
                            'onboarding_finish_disclaimer'.tr(),
                            style: tt.bodySmall?.copyWith(
                              color: colors.textSecondary,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
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
