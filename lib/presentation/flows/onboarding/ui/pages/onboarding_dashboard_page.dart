import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_feature_page.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_feature_row.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_portfolio_preview.dart';

/// La cartera: cómo se ve la Home, cómo se carga (a mano o desde eToro) y
/// la comparación con el mercado.
class OnboardingDashboardPage extends StatelessWidget {
  const OnboardingDashboardPage({super.key, required this.activePage});

  static const pageIndex = 1;

  final int activePage;

  @override
  Widget build(BuildContext context) {
    return OnboardingFeaturePage(
      pageIndex: pageIndex,
      activePage: activePage,
      title: 'onboarding_dashboard_title'.tr(),
      subtitle: 'onboarding_dashboard_subtitle'.tr(),
      showcase: const OnboardingPortfolioPreview(),
      features: [
        OnboardingFeatureRow(
          icon: Icons.add_rounded,
          title: 'onboarding_dashboard_feature_add_title'.tr(),
          subtitle: 'onboarding_dashboard_feature_add_subtitle'.tr(),
        ),
        // La alternativa a cargar a mano: traer la cartera entera.
        OnboardingFeatureRow(
          icon: Icons.sync_alt_rounded,
          title: 'onboarding_dashboard_feature_etoro_title'.tr(),
          subtitle: 'onboarding_dashboard_feature_etoro_subtitle'.tr(),
          tag: 'onboarding_tag_premium'.tr(),
        ),
        OnboardingFeatureRow(
          icon: Icons.stacked_line_chart_rounded,
          title: 'onboarding_dashboard_feature_benchmark_title'.tr(),
          subtitle: 'onboarding_dashboard_feature_benchmark_subtitle'.tr(),
          tag: 'onboarding_tag_premium'.tr(),
        ),
      ],
    );
  }
}
