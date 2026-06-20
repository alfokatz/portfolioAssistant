import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/charts/portfolio_area_line_chart.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/pnl_badge.dart';

class PortfolioHeroSection extends StatelessWidget {
  final PortfolioSummary summary;
  final List<double> chartValues;
  final double periodPnlAbsolute;
  final double periodPnlPercent;

  const PortfolioHeroSection({
    super.key,
    required this.summary,
    required this.chartValues,
    required this.periodPnlAbsolute,
    required this.periodPnlPercent,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final colors = context.customColors;
    final pnl = periodPnlAbsolute;
    final sign = pnl >= 0 ? '+' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'portfolio_total_label'.tr(),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: PortfolioColors.textSecondary,
                      letterSpacing: 0.3,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                currency.format(summary.totalValue),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: PortfolioColors.textPrimary,
                      fontSize: 44,
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colors.pnlColor(pnl),
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                  const SizedBox(width: 10),
                  PnlBadge(percent: periodPnlPercent),
                ],
              ),
              const SizedBox(height: 16),
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
      ],
    );
  }
}
