import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/benchmark_point.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/utils/home_chart_utils.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/home_chart_card.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/pnl_badge.dart';

class BenchmarkComparisonCard extends StatelessWidget {
  final double portfolioPercent;
  final List<BenchmarkPoint> benchmarkPoints;

  const BenchmarkComparisonCard({
    super.key,
    required this.portfolioPercent,
    required this.benchmarkPoints,
  });

  @override
  Widget build(BuildContext context) {
    final returns = HomeChartUtils.benchmarkComparisonReturns(
      portfolioPercent: portfolioPercent,
      benchmarkPoints: benchmarkPoints,
    );
    if (returns == null) return const SizedBox.shrink();

    return HomeChartCard(
      title: 'chart_benchmark_title'.tr(),
      child: Column(
        children: [
          _BenchmarkStatRow(
            label: 'chart_benchmark_portfolio'.tr(),
            percent: returns.portfolioPercent,
            accentColor: PortfolioColors.chartLine,
          ),
          const SizedBox(height: 10),
          _BenchmarkStatRow(
            label: 'chart_benchmark_sp500'.tr(),
            percent: returns.sp500Percent,
            accentColor: PortfolioColors.benchmarkSp500,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: PortfolioColors.border),
          ),
          _BenchmarkStatRow(
            label: 'chart_benchmark_difference'.tr(),
            percent: returns.differencePercent,
            accentColor: context.customColors.pnlColor(returns.differencePercent),
            emphasized: true,
            trailing: PnlBadge(percent: returns.differencePercent, compact: true),
          ),
        ],
      ),
    );
  }
}

class _BenchmarkStatRow extends StatelessWidget {
  const _BenchmarkStatRow({
    required this.label,
    required this.percent,
    required this.accentColor,
    this.emphasized = false,
    this.trailing,
  });

  final String label;
  final double percent;
  final Color accentColor;
  final bool emphasized;
  final Widget? trailing;

  String _formatPercent(double value) {
    final sign = value >= 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final valueColor = colors.pnlColor(percent);

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: emphasized
                      ? PortfolioColors.textPrimary
                      : PortfolioColors.textSecondary,
                  fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
                ),
          ),
        ),
        if (trailing != null)
          trailing!
        else
          Text(
            _formatPercent(percent),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: valueColor,
                  fontWeight: FontWeight.w700,
                ),
          ),
      ],
    );
  }
}
