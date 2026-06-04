import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/shared/charts/chart_axis_helper.dart';
import 'package:portfolio_assistant/presentation/shared/charts/chart_with_y_axis.dart';

class PortfolioAreaLineChart extends StatelessWidget {
  final List<double> values;
  final double height;
  final Color lineColor;
  final bool showYAxisLabels;

  const PortfolioAreaLineChart({
    super.key,
    required this.values,
    this.height = 160,
    this.lineColor = PortfolioColors.chartLine,
    this.showYAxisLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(height: height);
    }

    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.08;
    final chartMinY = minY - padding;
    final chartMaxY = maxY + padding;

    final spots =
        values.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList();

    final lineChart = LineChart(
      LineChartData(
        gridData: showYAxisLabels
            ? ChartAxisHelper.horizontalGrid(
                minY: chartMinY,
                maxY: chartMaxY,
              )
            : const FlGridData(show: false),
        titlesData: showYAxisLabels
            ? ChartTitlesWithoutLeftAxis.none
            : const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minY: chartMinY,
        maxY: chartMaxY,
        baselineY: chartMinY,
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: lineColor,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  lineColor.withValues(alpha: 0.35),
                  lineColor.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (!showYAxisLabels) {
      return SizedBox(height: height, width: double.infinity, child: lineChart);
    }

    return ChartWithYAxis(
      height: height,
      minY: chartMinY,
      maxY: chartMaxY,
      formatter: ChartAxisHelper.formatCurrency,
      chart: lineChart,
    );
  }
}
