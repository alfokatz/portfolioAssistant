import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_feature_page.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_feature_row.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_notifications_preview.dart';

/// Lo que Porty hace sin que se lo pidan: alertas de precio, el informe de
/// la semana y los avisos cuando algo de la cartera se mueve fuerte.
class OnboardingAlertsPage extends StatelessWidget {
  const OnboardingAlertsPage({super.key, required this.activePage});

  static const pageIndex = 4;

  final int activePage;

  @override
  Widget build(BuildContext context) {
    return OnboardingFeaturePage(
      pageIndex: pageIndex,
      activePage: activePage,
      title: 'onboarding_alerts_title'.tr(),
      subtitle: 'onboarding_alerts_subtitle'.tr(),
      showcase: const OnboardingNotificationsPreview(),
      features: [
        OnboardingFeatureRow(
          icon: Icons.notifications_none_rounded,
          title: 'onboarding_alerts_feature_price_title'.tr(),
          subtitle: 'onboarding_alerts_feature_price_subtitle'.tr(
            namedArgs: {
              'free':
                  '${PlanMatrix.plans[SubscriptionTier.free]!.priceAlertLimit}',
              'premium':
                  '${PlanMatrix.plans[SubscriptionTier.premium]!.priceAlertLimit}',
            },
          ),
        ),
        OnboardingFeatureRow(
          icon: Icons.event_note_outlined,
          title: 'onboarding_alerts_feature_weekly_title'.tr(),
          subtitle: 'onboarding_alerts_feature_weekly_subtitle'.tr(),
          tag: 'onboarding_tag_gold'.tr(),
        ),
      ],
    );
  }
}
