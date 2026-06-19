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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            currency.format(summary.totalValue),
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: PortfolioColors.textPrimary,
                  fontSize: 38,
                  height: 1.05,
                  letterSpacing: -0.8,
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
                    ),
              ),
              const SizedBox(width: 10),
              PnlBadge(percent: periodPnlPercent),
            ],
          ),
          const SizedBox(height: 8),
          PortfolioAreaLineChart(
            key: ValueKey(
              chartValues.isEmpty
                  ? 'empty'
                  : '${chartValues.length}_${chartValues.last}',
            ),
            values: chartValues,
          ),
        ],
      ),
    );
  }
}
