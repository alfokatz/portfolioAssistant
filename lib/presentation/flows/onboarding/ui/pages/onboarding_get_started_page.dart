import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/providers/onboarding_provider.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_action_card.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_entrance.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/surface_card.dart';

class OnboardingGetStartedPage extends StatelessWidget {
  const OnboardingGetStartedPage({
    super.key,
    required this.activePage,
    required this.onExit,
    this.isFinishing = false,
  });

  static const pageIndex = 3;

  final int activePage;
  final ValueChanged<OnboardingExit> onExit;
  final bool isFinishing;

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
            Row(
              children: [
                Container(
                  width: AppDimens.touchTarget,
                  height: AppDimens.touchTarget,
                  decoration: BoxDecoration(
                    color: colors.surfaceElevated,
                    borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                    border: Border.all(color: colors.border),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: colors.accentBlue,
                    size: AppDimens.iconMd,
                  ),
                ),
                const SizedBox(width: AppDimens.sp12),
                Text(
                  'app_name'.tr(),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.sectionGap),
            Text(
              'onboarding_finish_title'.tr(),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.02,
                  ),
            ),
            const SizedBox(height: AppDimens.sp12),
            Text(
              'onboarding_finish_subtitle'.tr(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: AppDimens.sp24),
            OnboardingActionCard(
              isPrimary: true,
              icon: Icons.add_rounded,
              title: 'onboarding_finish_add_title'.tr(),
              subtitle: 'onboarding_finish_add_subtitle'.tr(),
              enabled: !isFinishing,
              onTap: () => onExit(OnboardingExit.addPosition),
            ),
            const SizedBox(height: AppDimens.sp12),
            OnboardingActionCard(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'onboarding_finish_assistant_title'.tr(),
              subtitle: 'onboarding_finish_assistant_subtitle'.tr(),
              enabled: !isFinishing,
              onTap: () => onExit(OnboardingExit.assistant),
            ),
            const SizedBox(height: AppDimens.sp20),
            SurfaceCard(
              padding: const EdgeInsets.all(AppDimens.cardPadding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: AppDimens.iconMd,
                    color: colors.accentBlue,
                  ),
                  const SizedBox(width: AppDimens.sp12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'onboarding_finish_disclaimer'.tr(),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colors.textSecondary,
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: AppDimens.sp6),
                        Text(
                          'onboarding_finish_disclaimer_note'.tr(),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: colors.textSecondary,
                                height: 1.35,
                              ),
                        ),
                      ],
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
