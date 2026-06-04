import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/shared/charts/chart_axis_helper.dart';
import 'package:portfolio_assistant/presentation/shared/charts/chart_with_y_axis.dart';

class BenchmarkDualLineChart extends StatelessWidget {
  final List<double> portfolioValues;
  final List<double> sp500Values;
  final double height;

  const BenchmarkDualLineChart({
    super.key,
    required this.portfolioValues,
    required this.sp500Values,
    this.height = 120,
  });

  @override
  Widget build(BuildContext context) {
    if (portfolioValues.length < 2 || sp500Values.length < 2) {
      return SizedBox(height: height);
    }

    final count = portfolioValues.length < sp500Values.length
        ? portfolioValues.length
        : sp500Values.length;

    final all = [
      ...portfolioValues.take(count),
      ...sp500Values.take(count),
    ];
    final minY = all.reduce((a, b) => a < b ? a : b);
    final maxY = all.reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.05;
    final chartMinY = minY - padding;
    final chartMaxY = maxY + padding;

    final portfolioSpots = List<FlSpot>.generate(
      count,
      (i) => FlSpot(i.toDouble(), portfolioValues[i]),
    );
    final spSpots = List<FlSpot>.generate(
      count,
      (i) => FlSpot(i.toDouble(), sp500Values[i]),
    );

    return ChartWithYAxis(
      height: height,
      minY: chartMinY,
      maxY: chartMaxY,
      formatter: (v) => ChartAxisHelper.formatIndex(
        v,
        range: chartMaxY - chartMinY,
      ),
      chart: LineChart(
        LineChartData(
          gridData: ChartAxisHelper.horizontalGrid(
            minY: chartMinY,
            maxY: chartMaxY,
          ),
          titlesData: ChartTitlesWithoutLeftAxis.none,
          borderData: FlBorderData(show: false),
          minY: chartMinY,
          maxY: chartMaxY,
          baselineY: chartMinY,
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: portfolioSpots,
              isCurved: true,
              color: PortfolioColors.chartLine,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: spSpots,
              isCurved: true,
              color: PortfolioColors.benchmarkSp500,
              barWidth: 2,
              dashArray: [6, 4],
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}

class BenchmarkLegend extends StatelessWidget {
  const BenchmarkLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LegendItem(
          color: PortfolioColors.chartLine,
          label: 'PORTFOLIO',
          dashed: false,
        ),
        const SizedBox(width: 16),
        _LegendItem(
          color: PortfolioColors.benchmarkSp500,
          label: 'S&P 500',
          dashed: true,
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.dashed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dashed)
          SizedBox(
            width: 16,
            height: 2,
            child: CustomPaint(painter: _DashedLinePainter(color: color)),
          )
        else
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: PortfolioColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
        ),
      ],
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;

  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const dash = 3.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(x + dash, size.height / 2),
        paint,
      );
      x += dash * 2;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
