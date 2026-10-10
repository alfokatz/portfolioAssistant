import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/charts/chart_axis_helper.dart';
import 'package:portfolio_assistant/presentation/shared/charts/chart_with_y_axis.dart';

/// Línea con área del valor de la cartera. La curva suaviza sin pasarse de
/// los datos (sin picos ni valles que no existieron). Con [onScrub], se
/// recorre arrastrando el dedo en horizontal: avisa el índice del punto y
/// marca ese día con una línea y un punto ([scrubIndex]).
class PortfolioAreaLineChart extends StatelessWidget {
  final List<double> values;
  final double height;
  final Color? lineColor;
  final bool showYAxisLabels;

  /// Índice del punto que se está recorriendo, o `null` al soltar.
  final ValueChanged<int?>? onScrub;
  final int? scrubIndex;

  /// Línea punteada en el valor de inicio del período: de un vistazo, si
  /// estás arriba o abajo de donde arrancaste (como en el gráfico de precio
  /// de una acción).
  final bool showStartReference;

  const PortfolioAreaLineChart({
    super.key,
    required this.values,
    this.height = 160,
    this.lineColor,
    this.showYAxisLabels = true,
    this.onScrub,
    this.scrubIndex,
    this.showStartReference = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final effectiveLineColor = lineColor ?? colors.chartLine;

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
                gridColor: colors.chartGrid,
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
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (showStartReference)
              HorizontalLine(
                y: values.first,
                color: colors.textSecondary.withValues(alpha: 0.45),
                strokeWidth: 1,
                dashArray: const [4, 4],
              ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            // Suaviza sin inventar: sin esto la curva dibujaba máximos y
            // mínimos entre dos puntos que la cartera nunca tuvo.
            preventCurveOverShooting: true,
            color: effectiveLineColor,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  effectiveLineColor.withValues(alpha: 0.08),
                  effectiveLineColor.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (!showYAxisLabels) {
      final chart = SizedBox(
        height: height,
        width: double.infinity,
        child: lineChart,
      );
      final onScrub = this.onScrub;
      if (onScrub == null) return chart;
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          int indexAt(double dx) =>
              ((dx / width).clamp(0.0, 1.0) * (values.length - 1)).round();
          // Arrastre horizontal: no compite con el scroll vertical de la
          // pantalla.
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) => onScrub(indexAt(d.localPosition.dx)),
            onHorizontalDragUpdate:
                (d) => onScrub(indexAt(d.localPosition.dx)),
            onHorizontalDragEnd: (_) => onScrub(null),
            onHorizontalDragCancel: () => onScrub(null),
            child: Stack(
              children: [
                chart,
                if (scrubIndex != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _ScrubPainter(
                          fractionX: scrubIndex! / (values.length - 1),
                          fractionY:
                              (values[scrubIndex!] - chartMinY) /
                              (chartMaxY - chartMinY),
                          color: effectiveLineColor,
                          haloColor: colors.surfaceCard,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
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

/// La marca del día recorrido: una línea vertical fina y un punto sobre la
/// curva (la curva pasa por los puntos de datos).
class _ScrubPainter extends CustomPainter {
  _ScrubPainter({
    required this.fractionX,
    required this.fractionY,
    required this.color,
    required this.haloColor,
  });

  final double fractionX;
  final double fractionY;
  final Color color;
  final Color haloColor;

  @override
  void paint(Canvas canvas, Size size) {
    final x = fractionX * size.width;
    final y = (1 - fractionY) * size.height;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(Offset(x, y), 6, Paint()..color = haloColor);
    canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ScrubPainter old) =>
      old.fractionX != fractionX ||
      old.fractionY != fractionY ||
      old.color != color;
}
