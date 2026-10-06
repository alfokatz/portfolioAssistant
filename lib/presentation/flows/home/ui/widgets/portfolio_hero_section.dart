import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/time_range_selector.dart';
import 'package:portfolio_assistant/presentation/shared/charts/portfolio_area_line_chart.dart';
import 'package:portfolio_assistant/presentation/shared/loading/skeleton.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/pnl_badge.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/skeleton_text.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';

/// La card del total: valor, variación del período, gráfico y selector de
/// rango. Con `summary` en `null` ([PortfolioHeroSection.skeleton]) es su
/// propio skeleton: misma card y alturas, valores en barras.
class PortfolioHeroSection extends StatelessWidget {
  final PortfolioSummary? summary;
  final List<double> chartValues;
  final double periodPnlAbsolute;
  final double periodPnlPercent;
  final ChartTimeRange selectedRange;
  final ValueChanged<ChartTimeRange> onRangeSelected;

  const PortfolioHeroSection({
    super.key,
    required this.summary,
    required this.chartValues,
    required this.periodPnlAbsolute,
    required this.periodPnlPercent,
    required this.selectedRange,
    required this.onRangeSelected,
  });

  const PortfolioHeroSection.skeleton({
    super.key,
    this.selectedRange = ChartTimeRange.m1,
  }) : summary = null,
       chartValues = const [],
       periodPnlAbsolute = 0,
       periodPnlPercent = 0,
       onRangeSelected = _ignoreRange;

  static void _ignoreRange(ChartTimeRange _) {}

  /// Alto del área del gráfico.
  static const chartHeight = 130.0;

  @override
  Widget build(BuildContext context) {
    final currency = AppNumberFormat.currency();
    final colors = context.customColors;
    final pnl = periodPnlAbsolute;
    final sign = pnl >= 0 ? '+' : '';
    final summary = this.summary;
    final skeleton = summary == null;
    final badgeStyle = Theme.of(context).textTheme.labelMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.pageHorizontal),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.9, -0.7),
            radius: 1.2,
            colors: [
              Color.lerp(colors.surfaceCard, colors.accentWarm, 0.22)!,
              colors.surfaceCard,
            ],
            stops: const [0.0, 0.85],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'portfolio_total_label'.tr(),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Los valores cambian en el lugar con un crossfade corto
                  // (caché → datos nuevos, o al refrescar).
                  SkeletonText(
                    skeleton ? null : currency.format(summary.totalValue),
                    animate: true,
                    placeholder: '\$00,000.00',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: colors.textPrimary,
                      fontSize: 40,
                      letterSpacing: -1.5,
                      height: 1.0,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SkeletonText(
                        skeleton ? null : '$sign${currency.format(pnl)}',
                        animate: true,
                        placeholder: '+\$000.00',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          color: colors.pnlColor(pnl),
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (skeleton)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: SkeletonText(
                            null,
                            placeholder: '+0.0%',
                            style: badgeStyle,
                          ),
                        )
                      else
                        PnlBadge(percent: periodPnlPercent),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            if (skeleton)
              const SizedBox(
                height: chartHeight,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: SkeletonBlock(radius: 12),
                ),
              )
            else
              PortfolioAreaLineChart(
                key: ValueKey(
                  chartValues.isEmpty
                      ? 'empty'
                      : '${chartValues.length}_${chartValues.last}',
                ),
                values: chartValues,
                showYAxisLabels: false,
                height: chartHeight,
              ),
            const SizedBox(height: 4),
            TimeRangeSelector(
              selected: selectedRange,
              onSelected: onRangeSelected,
            ),
          ],
        ),
      ),
    );
  }
}
