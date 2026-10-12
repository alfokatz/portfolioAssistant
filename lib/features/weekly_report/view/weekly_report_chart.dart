import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_portfolio_numbers.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/charts/diverging_bar.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';

/// La semana en un gráfico chico: tu cartera contra el S&P 500, las dos en
/// % desde el cierre del viernes anterior, con el valor final al lado de
/// cada línea. Mismos colores que la comparación de la Home
/// (`BenchmarkDualLineChart`): cartera en charcoal, S&P en benchmark gray.
///
/// Se puede recorrer con el dedo (como el gráfico de la Home): una línea
/// marca el día y los valores de la derecha pasan a ser los de ese día.
/// [onScrub] avisa qué día se está mirando (`null` al soltar).
class WeeklyReportChart extends StatelessWidget {
  const WeeklyReportChart({
    super.key,
    required this.points,
    required this.showSp500,
    this.height = 120,
    this.scrubIndex,
    this.onScrub,
  });

  final List<WeeklyDayPoint> points;

  /// Free no ve la comparación con el S&P 500 (es de Premium).
  final bool showSp500;
  final double height;

  /// El día que se está recorriendo, o `null`.
  final int? scrubIndex;
  final ValueChanged<int?>? onScrub;

  /// Ancho reservado a la derecha para los valores finales.
  static const labelWidth = 76.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    if (points.length < 2) return const SizedBox.shrink();
    final sp = [
      for (final p in points)
        if (p.sp500Pct != null) p.sp500Pct!,
    ];
    final withSp = showSp500 && sp.length == points.length;
    final values = [
      for (final p in points) p.portfolioPct,
      if (withSp) ...sp,
      0.0,
    ];
    var minY = values.reduce(math.min);
    var maxY = values.reduce(math.max);
    // Una semana casi plana no se tiene que ver como una montaña rusa.
    final span = math.max(maxY - minY, 1.0);
    final pad = span * 0.12;
    minY -= pad;
    maxY += pad;

    LineChartBarData line(List<double> ys, Color color, double width) =>
        LineChartBarData(
          spots: [
            for (var i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i]),
          ],
          isCurved: true,
          curveSmoothness: 0.25,
          color: color,
          barWidth: width,
          dotData: const FlDotData(show: false),
        );

    final mine = [for (final p in points) p.portfolioPct];
    final scrub = scrubIndex?.clamp(0, points.length - 1);
    // Recorriendo, los valores de la derecha son los del día marcado.
    final lastMine = mine[scrub ?? mine.length - 1];
    final lastSp = withSp ? sp[scrub ?? sp.length - 1] : null;

    final semantics = [
      'weekly_report_chart_semantics_you'.tr(
        namedArgs: {'pct': AppNumberFormat.percent(lastMine)},
      ),
      if (lastSp != null)
        'weekly_report_chart_semantics_sp'.tr(
          namedArgs: {'pct': AppNumberFormat.percent(lastSp)},
        ),
    ].join('. ');

    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            double yOf(double v) => (1 - (v - minY) / (maxY - minY)) * height;
            // Etiquetas al final de cada línea, sin pisarse.
            const labelHeight = 18.0;
            var yMine = yOf(lastMine) - labelHeight / 2;
            double? ySp = lastSp == null ? null : yOf(lastSp) - labelHeight / 2;
            if (ySp != null && (yMine - ySp).abs() < labelHeight) {
              final mid = (yMine + ySp) / 2;
              final up = yMine < ySp;
              yMine = mid + (up ? -labelHeight / 2 : labelHeight / 2);
              ySp = mid + (up ? labelHeight / 2 : -labelHeight / 2);
            }
            double clampY(double y) =>
                y.clamp(0.0, height - labelHeight).toDouble();

            final tt = Theme.of(context).textTheme;
            final labelStyle = tt.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            );
            return Stack(
              children: [
                Positioned.fill(
                  right: labelWidth,
                  child: _Scrubbable(
                    count: points.length,
                    onScrub: onScrub,
                    child: LineChart(
                      LineChartData(
                        minY: minY,
                        maxY: maxY,
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineTouchData: const LineTouchData(enabled: false),
                        // La línea de 0 %: dónde empezó la semana.
                        extraLinesData: ExtraLinesData(
                          verticalLines: [
                            if (scrub != null)
                              VerticalLine(
                                x: scrub.toDouble(),
                                color: colors.chartLine.withValues(alpha: 0.3),
                                strokeWidth: 1,
                              ),
                          ],
                          horizontalLines: [
                            HorizontalLine(
                              y: 0,
                              color: colors.border,
                              strokeWidth: 1,
                              dashArray: const [3, 4],
                            ),
                          ],
                        ),
                        lineBarsData: [
                          if (withSp) line(sp, colors.benchmarkSp500, 1.5),
                          line(mine, colors.chartLine, 2.25),
                        ],
                      ),
                      duration: Duration.zero,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  width: labelWidth - AppDimens.sp8,
                  top: clampY(yMine),
                  height: labelHeight,
                  child: Text(
                    AppNumberFormat.percent(lastMine),
                    maxLines: 1,
                    style: labelStyle?.copyWith(color: colors.chartLine),
                  ),
                ),
                if (lastSp != null && ySp != null)
                  Positioned(
                    right: 0,
                    width: labelWidth - AppDimens.sp8,
                    top: clampY(ySp),
                    height: labelHeight,
                    child: Text(
                      'S&P ${AppNumberFormat.percent(lastSp)}',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: labelStyle?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Arrastre horizontal sobre el gráfico → qué día se está mirando. No
/// compite con el scroll vertical de la pantalla.
class _Scrubbable extends StatelessWidget {
  const _Scrubbable({
    required this.count,
    required this.onScrub,
    required this.child,
  });

  final int count;
  final ValueChanged<int?>? onScrub;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onScrub = this.onScrub;
    if (onScrub == null || count < 2) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        int indexAt(double dx) =>
            ((dx / constraints.maxWidth).clamp(0.0, 1.0) * (count - 1)).round();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => onScrub(indexAt(d.localPosition.dx)),
          onHorizontalDragUpdate: (d) => onScrub(indexAt(d.localPosition.dx)),
          onHorizontalDragEnd: (_) => onScrub(null),
          onHorizontalDragCancel: () => onScrub(null),
          child: child,
        );
      },
    );
  }
}

/// Barra divergente (centro en 0) de cuánto empujó o frenó una posición a
/// la cartera: reemplaza el "+0,9 pts a tu cartera". Larga = mucho impacto.
class WeeklyImpactBar extends StatelessWidget {
  const WeeklyImpactBar({
    super.key,
    required this.contribution,
    required this.maxAbs,
  });

  final double contribution;

  /// La contribución más grande en valor absoluto entre las filas (la barra
  /// más larga llega al borde).
  final double maxAbs;

  static const height = 6.0;

  @override
  Widget build(BuildContext context) =>
      DivergingBar(value: contribution, maxAbs: maxAbs, height: height);
}
