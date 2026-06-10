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
  static const int compactItemLimit = 6;
  static const double minBarSlotWidth = 48;
  static const double maxBarWidth = 22;
  static const double minBarWidth = 14;
  static const double bottomReservedSize = 34;

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
    final needsScroll = items.length > compactItemLimit;

    return LayoutBuilder(
      builder: (context, constraints) {
        const axisWidth = 52.0;
        const axisGap = 4.0;
        final chartAreaWidth = constraints.maxWidth - axisWidth - axisGap;
        final contentWidth = needsScroll
            ? items.length * minBarSlotWidth
            : chartAreaWidth;
        final slotWidth = contentWidth / items.length;
        final barWidth =
            (slotWidth * 0.55).clamp(minBarWidth, maxBarWidth).toDouble();

        final barChart = BarChart(
          _barChartData(
            context: context,
            colors: colors,
            chartMinY: chartMinY,
            chartMaxY: chartMaxY,
            barWidth: barWidth,
            labelMaxWidth: slotWidth - 6,
          ),
        );

        final chartBody = needsScroll
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  width: contentWidth,
                  height: height,
                  child: barChart,
                ),
              )
            : SizedBox(height: height, child: barChart);

        return ChartWithYAxis(
          height: height,
          minY: chartMinY,
          maxY: chartMaxY,
          formatter: ChartAxisHelper.formatSignedCurrency,
          chart: chartBody,
        );
      },
    );
  }

  BarChartData _barChartData({
    required BuildContext context,
    required CustomColors colors,
    required double chartMinY,
    required double chartMaxY,
    required double barWidth,
    required double labelMaxWidth,
  }) {
    return BarChartData(
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
            reservedSize: bottomReservedSize,
            getTitlesWidget: (value, meta) {
              final i = value.toInt();
              if (i < 0 || i >= items.length) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                space: 4,
                child: SizedBox(
                  width: labelMaxWidth,
                  child: Text(
                    items[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: PortfolioColors.textSecondary,
                          fontSize: 11,
                        ),
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
              width: barWidth,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        );
      }).toList(),
    );
  }
}
