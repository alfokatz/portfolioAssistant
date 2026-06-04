import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/charts/chart_axis_helper.dart';
import 'package:portfolio_assistant/presentation/shared/charts/chart_with_y_axis.dart';

class PnlBarChartItem {
  final String label;
  final double value;

  const PnlBarChartItem({required this.label, required this.value});
}

class PnlBarChart extends StatelessWidget {
  final List<PnlBarChartItem> items;
  final double height;

  const PnlBarChart({
    super.key,
    required this.items,
    this.height = 140,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return SizedBox(height: height);
    }

    final colors = context.customColors;
    final maxAbs =
        items.map((i) => i.value.abs()).reduce((a, b) => a > b ? a : b);
    final maxY = maxAbs * 1.25;
    final chartMinY = -maxY;
    final chartMaxY = maxY;

    return ChartWithYAxis(
      height: height,
      minY: chartMinY,
      maxY: chartMaxY,
      formatter: ChartAxisHelper.formatSignedCurrency,
      chart: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: chartMaxY,
          minY: chartMinY,
          gridData: ChartAxisHelper.horizontalGrid(
            minY: chartMinY,
            maxY: chartMaxY,
            divisions: 4,
          ),
          titlesData: FlTitlesData(
            show: true,
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false, reservedSize: 0),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= items.length) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    space: 4,
                    child: Text(
                      items[i].label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: PortfolioColors.textSecondary,
                            fontSize: 11,
                          ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: items.asMap().entries.map((entry) {
            final v = entry.value.value;
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: v,
                  color: colors.pnlColor(v),
                  width: 20,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
