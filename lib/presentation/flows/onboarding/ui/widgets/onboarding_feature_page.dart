import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_mockup_widgets.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_entrance.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_header.dart';

/// Esqueleto de una página de funcionalidad: título, un caso de uso de
/// ejemplo ([showcase], marcado como ejemplo) y las funciones que lo
/// completan ([features]), todo con la entrada escalonada.
class OnboardingFeaturePage extends StatelessWidget {
  const OnboardingFeaturePage({
    super.key,
    required this.pageIndex,
    required this.activePage,
    required this.title,
    required this.subtitle,
    required this.showcase,
    this.tag,
    this.features = const [],
  });

  final int pageIndex;
  final int activePage;
  final String title;
  final String subtitle;
  final String? tag;
  final Widget showcase;
  final List<Widget> features;

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
              OnboardingPageHeader(title: title, subtitle: subtitle, tag: tag),
            ),
            const SizedBox(height: AppDimens.sp24),
            enter(
              1,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const OnboardingSampleCaption(),
                  const SizedBox(height: AppDimens.sp8),
                  showcase,
                ],
              ),
            ),
            for (final (i, feature) in features.indexed) ...[
              SizedBox(height: i == 0 ? AppDimens.sp28 : AppDimens.sp20),
              enter(2 + i, feature),
            ],
          ],
        ),
      ),
    );
  }
}
