import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/pnl_badge.dart';

/// Gráfico decorativo estático para mockups del onboarding.
class OnboardingMiniLineChart extends StatelessWidget {
  const OnboardingMiniLineChart({
    super.key,
    required this.values,
    this.height = 100,
    this.showArea = true,
    this.lineColor = PortfolioColors.chartLine,
  });

  final List<double> values;
  final double height;
  final bool showArea;
  final Color lineColor;

  static const _defaultValues = [
    0.72,
    0.68,
    0.74,
    0.71,
    0.78,
    0.82,
    0.79,
    0.88,
    0.92,
    1.0,
  ];

  factory OnboardingMiniLineChart.upward({double height = 100}) {
    return OnboardingMiniLineChart(
      values: _defaultValues,
      height: height,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(height: height);

    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.12;
    final spots = values
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          minY: minY - padding,
          maxY: maxY + padding,
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: lineColor,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: showArea
                  ? BarAreaData(
                      show: true,
                      color: lineColor.withValues(alpha: 0.12),
                    )
                  : BarAreaData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mockup de teléfono para la pantalla de bienvenida.
class OnboardingPhoneMockup extends StatelessWidget {
  const OnboardingPhoneMockup({super.key});

  @override
  Widget build(BuildContext context) {
    const currency = r'$12,450';
    const pnlAbs = r'+$320';
    const pnlPct = 3.2;

    return Container(
      width: 240,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: PortfolioColors.surfaceElevated,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: PortfolioColors.border, width: 2),
        boxShadow: [
          BoxShadow(
            color: PortfolioColors.accentBlue.withValues(alpha: 0.15),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        decoration: BoxDecoration(
          color: PortfolioColors.background,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: PortfolioColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'onboarding_mock_total_label'.tr(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: PortfolioColors.textSecondary,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              currency,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: PortfolioColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  pnlAbs,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: context.customColors.pnlColor(1),
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 8),
                const PnlBadge(percent: pnlPct),
              ],
            ),
            const SizedBox(height: 16),
            OnboardingMiniLineChart.upward(height: 88),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PortfolioColors.surfaceCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: PortfolioColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: PortfolioColors.accentBlue.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'onboarding_mock_insight_title'.tr(),
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: PortfolioColors.accentBlue,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'onboarding_mock_insight_body'.tr(),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: PortfolioColors.textSecondary,
                                    height: 1.3,
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
