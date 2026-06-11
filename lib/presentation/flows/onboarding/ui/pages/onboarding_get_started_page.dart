import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/providers/onboarding_provider.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_action_card.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_entrance.dart';

class OnboardingGetStartedPage extends StatelessWidget {
  const OnboardingGetStartedPage({
    super.key,
    required this.activePage,
    required this.onExit,
  });

  static const pageIndex = 3;

  final int activePage;
  final ValueChanged<OnboardingExit> onExit;

  @override
  Widget build(BuildContext context) {
    return OnboardingPageEntrance(
      pageIndex: pageIndex,
      activePage: activePage,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      PortfolioColors.accentBlue.withValues(alpha: 0.9),
                      PortfolioColors.accentBlueDim,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: PortfolioColors.textPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'app_name'.tr(),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: PortfolioColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'onboarding_finish_title'.tr(),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: PortfolioColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            'onboarding_finish_subtitle'.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: PortfolioColors.textSecondary,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 24),
          OnboardingActionCard(
            isPrimary: true,
            icon: Icons.add_rounded,
            title: 'onboarding_finish_add_title'.tr(),
            subtitle: 'onboarding_finish_add_subtitle'.tr(),
            onTap: () => onExit(OnboardingExit.addPosition),
          ),
          const SizedBox(height: 12),
          OnboardingActionCard(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'onboarding_finish_assistant_title'.tr(),
            subtitle: 'onboarding_finish_assistant_subtitle'.tr(),
            onTap: () => onExit(OnboardingExit.assistant),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: PortfolioColors.surfaceCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PortfolioColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 20,
                  color: PortfolioColors.accentBlue.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'onboarding_finish_disclaimer'.tr(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: PortfolioColors.textSecondary,
                              height: 1.4,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'onboarding_finish_disclaimer_note'.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: PortfolioColors.textSecondary
                                  .withValues(alpha: 0.85),
                              height: 1.35,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
        ),
      ),
    );
  }
}
