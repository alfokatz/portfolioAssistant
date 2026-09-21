import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/time_range_selector.dart';
import 'package:portfolio_assistant/presentation/shared/charts/portfolio_area_line_chart.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/pnl_badge.dart';

class PortfolioHeroSection extends StatelessWidget {
  final PortfolioSummary summary;
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

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final colors = context.customColors;
    final pnl = periodPnlAbsolute;
    final sign = pnl >= 0 ? '+' : '';

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
                  Text(
                    currency.format(summary.totalValue),
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
                      Text(
                        '$sign${currency.format(pnl)}',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          color: colors.pnlColor(pnl),
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 10),
                      PnlBadge(percent: periodPnlPercent),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            PortfolioAreaLineChart(
              key: ValueKey(
                chartValues.isEmpty
                    ? 'empty'
                    : '${chartValues.length}_${chartValues.last}',
              ),
              values: chartValues,
              showYAxisLabels: false,
              height: 130,
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
