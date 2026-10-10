import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/charts/diverging_bar.dart';
import 'package:portfolio_assistant/presentation/shared/charts/portfolio_area_line_chart.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/pnl_badge.dart';

/// Datos de ejemplo de los mockups del onboarding: una cartera inventada
/// (y así se presenta, nunca como dato real del usuario).
abstract final class _Sample {
  static const values = <double>[
    12130, 12090, 12160, 12210, 12180, 12150, 12240, 12300, 12270, 12330,
    12380, 12350, 12410, 12450,
  ];
}

/// Card base de los mockups: la misma superficie que las cards de la app.
class _MockCard extends StatelessWidget {
  const _MockCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

/// Avatar con monograma, sin pedir el logo (el onboarding no sale a la red).
Widget _avatar(String ticker, double size) => QaTickerAvatar(
  ticker: ticker,
  size: size,
  brand: CompanyBrand(ticker: ticker),
);

/// La card del total de la Home en chico: el valor, la variación del
/// período y el gráfico con la línea de inicio.
class OnboardingPortfolioPreview extends StatelessWidget {
  const OnboardingPortfolioPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    const tabular = [FontFeature.tabularFigures()];

    return ExcludeSemantics(
      child: Column(
        children: [
          _MockCard(
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
                        style: tt.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        r'$12,450.00',
                        style: tt.displaySmall?.copyWith(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.8,
                          color: colors.textPrimary,
                          fontFeatures: tabular,
                        ),
                      ),
                      const SizedBox(height: AppDimens.sp6),
                      Wrap(
                        spacing: AppDimens.sp8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            r'+$320.00',
                            style: tt.bodyMedium?.copyWith(
                              color: colors.pnlColor(1),
                              fontWeight: FontWeight.w600,
                              fontFeatures: tabular,
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
                  values: _Sample.values,
                  showYAxisLabels: false,
                  showStartReference: true,
                  height: 84,
                ),
                const SizedBox(height: AppDimens.sp12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una conversación de ejemplo con Porty: la pregunta del usuario, la
/// respuesta al lado del avatar y una card como las del chat.
class OnboardingChatPreview extends StatelessWidget {
  const OnboardingChatPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    QaColors.resolve(Theme.of(context).brightness);
    const tabular = [FontFeature.tabularFigures()];

    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.sp16,
                vertical: AppDimens.sp12,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                borderRadius: BorderRadius.circular(AppDimens.radiusXl),
              ),
              child: Text(
                'onboarding_chat_question'.tr(),
                style: tt.bodyMedium?.copyWith(color: colors.textPrimary),
              ),
            ),
          ),
          const SizedBox(height: AppDimens.sp16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PortyAvatar(size: 32, state: PortyAvatarState.answered),
              const SizedBox(width: AppDimens.sp12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    'onboarding_chat_answer'.tr(),
                    style: tt.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.sp12),
          _MockCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'weekly_report_movers_section'.tr(),
                  style: tt.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppDimens.sp12),
                for (final (ticker, pct, impact) in const [
                  ('NVDA', '+4.5%', 1.8),
                ]) ...[
                  Row(
                    children: [
                      _avatar(ticker, 28),
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
                        pct,
                        style: tt.titleSmall?.copyWith(
                          color: colors.pnlColor(impact),
                          fontWeight: FontWeight.w700,
                          fontFeatures: tabular,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.sp8),
                  DivergingBar(value: impact, maxAbs: 1.8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
