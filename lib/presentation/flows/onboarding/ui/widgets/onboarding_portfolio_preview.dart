import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_mockup_widgets.dart';
import 'package:portfolio_assistant/presentation/shared/charts/portfolio_area_line_chart.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/pnl_badge.dart';

/// La Home en chico: el total con la variación del mes y el gráfico, y
/// debajo, en la misma card, las posiciones con lo que gana cada una.
class OnboardingPortfolioPreview extends StatelessWidget {
  const OnboardingPortfolioPreview({super.key});

  static const _values = <double>[
    12130,
    12090,
    12160,
    12210,
    12180,
    12150,
    12240,
    12300,
    12270,
    12330,
    12380,
    12350,
    12410,
    12450,
  ];

  static const _positions = [
    ('VOO', 6_120.0, 8.4),
    ('NVDA', 3_910.0, 21.7),
    ('AAPL', 2_420.0, -3.1),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;

    return ExcludeSemantics(
      child: OnboardingMockCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'portfolio_total_label'.tr(),
                    style: tt.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    QaFormat.price(12450),
                    style: tt.displaySmall?.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                      color: colors.textPrimary,
                      fontFeatures: onboardingTabular,
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp6),
                  Wrap(
                    spacing: AppDimens.sp8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        QaFormat.signedPrice(320),
                        style: tt.bodyMedium?.copyWith(
                          color: colors.pnlColor(1),
                          fontWeight: FontWeight.w600,
                          fontFeatures: onboardingTabular,
                        ),
                      ),
                      const PnlBadge(percent: 2.6),
                      Text(
                        'home_range_m1'.tr(),
                        style: tt.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const PortfolioAreaLineChart(
              values: _values,
              showYAxisLabels: false,
              showStartReference: true,
              height: 76,
            ),
            const SizedBox(height: AppDimens.sp8),
            Divider(height: 1, thickness: 0.5, color: colors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
              child: Column(
                children: [
                  for (final (i, (ticker, value, pct))
                      in _positions.indexed) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 0.5, color: colors.border),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          OnboardingTickerAvatar(ticker: ticker),
                          const SizedBox(width: AppDimens.sp12),
                          Expanded(
                            child: Text(
                              ticker,
                              style: tt.titleSmall?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            QaFormat.money(value),
                            style: tt.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontFeatures: onboardingTabular,
                            ),
                          ),
                          const SizedBox(width: AppDimens.sp8),
                          PnlBadge(percent: pct, compact: true),
                        ],
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
