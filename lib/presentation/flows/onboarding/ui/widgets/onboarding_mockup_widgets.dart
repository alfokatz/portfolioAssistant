import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/pnl_badge.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/surface_card.dart';

/// Gráfico decorativo estático para mockups del onboarding.
class OnboardingMiniLineChart extends StatelessWidget {
  const OnboardingMiniLineChart({
    super.key,
    required this.values,
    this.height = 100,
    this.showArea = true,
    this.lineColor,
  });

  final List<double> values;
  final double height;
  final bool showArea;
  final Color? lineColor;

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
    final colors = context.customColors;
    final effectiveLineColor = lineColor ?? colors.chartLine;

    if (values.length < 2) return SizedBox(height: height);

    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.12;
    final spots =
        values.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList();

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
              color: effectiveLineColor,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: showArea
                  ? BarAreaData(
                      show: true,
                      color: effectiveLineColor.withValues(alpha: 0.1),
                    )
                  : BarAreaData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vista previa editorial del snapshot del home (sin mockup de teléfono).
class OnboardingSnapshotPreview extends StatelessWidget {
  const OnboardingSnapshotPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    const currency = r'$12,450';
    const pnlAbs = r'+$320';
    const pnlPct = 3.2;

    return ExcludeSemantics(
      child: SurfaceCard(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.cardPadding,
        AppDimens.sp20,
        AppDimens.cardPadding,
        AppDimens.sp16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'portfolio_total_label'.tr(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(height: AppDimens.sp4),
          Text(
            currency,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
          const SizedBox(height: AppDimens.sp8),
          Row(
            children: [
              Text(
                pnlAbs,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.pnlColor(1),
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              const SizedBox(width: AppDimens.sp8),
              const PnlBadge(percent: pnlPct),
            ],
          ),
          const SizedBox(height: AppDimens.sp16),
          OnboardingMiniLineChart.upward(height: 88),
          const SizedBox(height: AppDimens.sp12),
          Divider(height: 1, color: colors.border),
          const SizedBox(height: AppDimens.sp12),
          Row(
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 18,
                color: colors.accentBlue,
              ),
              const SizedBox(width: AppDimens.sp8),
              Expanded(
                child: Text(
                  'onboarding_mock_insight_body'.tr(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        height: 1.35,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

/// Mock compacto del hero del dashboard para la página 2.
class OnboardingDashboardPreview extends StatelessWidget {
  const OnboardingDashboardPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    const selectedRange = ChartTimeRange.m1;

    return ExcludeSemantics(
      child: SurfaceCard(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'portfolio_total_label'.tr(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(height: AppDimens.sp6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                r'$42,190.50',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              const SizedBox(width: AppDimens.sp8),
              const Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: PnlBadge(percent: 12.4),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.sp16),
          OnboardingMiniLineChart.upward(height: 88),
          const SizedBox(height: AppDimens.sp12),
          Row(
            children: ChartTimeRange.values.map((range) {
              final isActive = range == selectedRange;
              return Expanded(
                child: Text(
                  range.label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isActive
                            ? colors.textPrimary
                            : colors.textSecondary,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                      ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppDimens.sp16),
          _PositionRow(
            ticker: 'AAPL',
            shares: '12',
            pnl: r'+$840',
            pnlColor: colors.pnlColor(1),
          ),
          Divider(height: 1, indent: 0, endIndent: 0, color: colors.border),
          _PositionRow(
            ticker: 'NVDA',
            shares: '5',
            pnl: r'+$1,240',
            pnlColor: colors.pnlColor(1),
          ),
        ],
        ),
      ),
    );
  }
}

class _PositionRow extends StatelessWidget {
  const _PositionRow({
    required this.ticker,
    required this.shares,
    required this.pnl,
    required this.pnlColor,
  });

  final String ticker;
  final String shares;
  final String pnl;
  final Color pnlColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.sp12),
      child: Row(
        children: [
          Text(
            ticker,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                ),
          ),
          const SizedBox(width: AppDimens.sp8),
          Text(
            shares,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const Spacer(),
          Text(
            pnl,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: pnlColor,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}
