import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/charts/chart_axis_helper.dart';

/// Wraps a chart and renders Y-axis reference labels on the left.
class ChartWithYAxis extends StatelessWidget {
  final double height;
  final double minY;
  final double maxY;
  final Widget chart;
  final String Function(double value) formatter;
  final double axisWidth;
  final int divisions;

  const ChartWithYAxis({
    super.key,
    required this.height,
    required this.minY,
    required this.maxY,
    required this.chart,
    required this.formatter,
    this.axisWidth = 52,
    this.divisions = 4,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final ticks = ChartAxisHelper.yTicks(minY, maxY, divisions: divisions);

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: axisWidth,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final tick in ticks.reversed)
                  Text(
                    formatter(tick),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          height: 1.1,
                        ),
                    textAlign: TextAlign.right,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(child: chart),
        ],
      ),
    );
  }
}

/// fl_chart titles without left axis — labels are drawn by [ChartWithYAxis].
abstract final class ChartTitlesWithoutLeftAxis {
  static const FlTitlesData none = FlTitlesData(
    show: true,
    leftTitles: AxisTitles(
      sideTitles: SideTitles(showTitles: false, reservedSize: 0),
    ),
    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
  );
}
