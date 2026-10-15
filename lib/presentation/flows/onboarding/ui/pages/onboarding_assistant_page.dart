import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_chat_use_cases.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_feature_page.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_feature_row.dart';

/// Porty: tres conversaciones de ejemplo para elegir (la cartera, cualquier
/// acción, el análisis de una empresa), con el plan que incluye cada una, y
/// lo que hace que las respuestas sean para el usuario.
class OnboardingAssistantPage extends StatelessWidget {
  const OnboardingAssistantPage({super.key, required this.activePage});

  static const pageIndex = 2;

  final int activePage;

  @override
  Widget build(BuildContext context) {
    return OnboardingFeaturePage(
      pageIndex: pageIndex,
      activePage: activePage,
      title: 'onboarding_assistant_title'.tr(),
      subtitle: 'onboarding_assistant_subtitle'.tr(),
      showcase: const OnboardingChatUseCases(),
      features: [
        OnboardingFeatureRow(
          icon: Icons.person_outline_rounded,
          title: 'onboarding_assistant_feature_memory_title'.tr(),
          subtitle: 'onboarding_assistant_feature_memory_subtitle'.tr(),
        ),
        OnboardingFeatureRow(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'onboarding_assistant_feature_actions_title'.tr(),
          subtitle: 'onboarding_assistant_feature_actions_subtitle'.tr(),
          tag: 'onboarding_tag_premium'.tr(),
        ),
      ],
    );
  }
}
