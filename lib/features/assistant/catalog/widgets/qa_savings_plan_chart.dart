import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/presentation/shared/animation/reveal_animation.dart';

/// Cómo crece un plan de ahorro: lo que el usuario pone (área tenue) contra
/// lo que vale con intereses (la línea del acento), la banda entre el
/// escenario pesimista y el optimista, y la meta punteada. La distancia
/// entre el área y la línea ES el interés compuesto — lo que el chart
/// lineal anterior no podía mostrar.
///
/// Se dibuja de izquierda a derecha la primera vez ([active] /
/// [onFinished], igual que el resto del catálogo); si después cambian los
/// [points] (el slider de aporte), se redibuja al instante.
class QaSavingsPlanChart extends StatefulWidget {
  const QaSavingsPlanChart({
    super.key,
    required this.points,
    required this.targetAmount,
    required this.startLabel,
    required this.endLabel,
    this.active = true,
    this.onFinished,
  });

  final List<PlanCurvePoint> points;
  final double targetAmount;
  final String startLabel;
  final String endLabel;
  final bool active;
  final VoidCallback? onFinished;

  @override
  State<QaSavingsPlanChart> createState() => _QaSavingsPlanChartState();
}

class _QaSavingsPlanChartState extends State<QaSavingsPlanChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  bool _started = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addStatusListener(_handleStatus);
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeStart();
  }

  @override
  void didUpdateWidget(covariant QaSavingsPlanChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeStart();
  }

  void _maybeStart() {
    if (_started || !widget.active) return;
    _started = true;
    startRevealAnimation(
      _controller,
      skip: MediaQuery.disableAnimationsOf(context),
      statusListener: _handleStatus,
      isMounted: () => mounted,
    );
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_finished) {
      _finished = true;
      widget.onFinished?.call();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 168,
      child: AnimatedBuilder(
        animation: _progress,
        builder:
            (context, _) => _PlanLineChart(
              points: widget.points,
              targetAmount: widget.targetAmount,
              startLabel: widget.startLabel,
              endLabel: widget.endLabel,
              progress: _progress.value,
            ),
      ),
    );
  }
}

class _PlanLineChart extends StatelessWidget {
  const _PlanLineChart({
    required this.points,
    required this.targetAmount,
    required this.startLabel,
    required this.endLabel,
    required this.progress,
  });

  final List<PlanCurvePoint> points;
  final double targetAmount;
  final String startLabel;
  final String endLabel;
  final double progress;

  static const _optimistic = 0;
  static const _pessimistic = 1;

  @override
  Widget build(BuildContext context) {
    final accent = QaColors.accentBlue;
    final contributedColor = QaColors.textSecondary;
    final maxX = points.last.month / 12;
    final maxY = [
      targetAmount,
      ...points.map((p) => p.values[PlanScenario.optimistic]!),
    ].reduce(math.max);

    List<FlSpot> spots(double Function(PlanCurvePoint) value) =>
        _visible([for (final p in points) FlSpot(p.month / 12, value(p))]);

    LineChartBarData hidden(List<FlSpot> s) => LineChartBarData(
      spots: s,
      color: Colors.transparent,
      barWidth: 0,
      dotData: const FlDotData(show: false),
    );

    return LineChart(
      duration: Duration.zero,
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: 0,
        maxY: maxY * 1.08,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: maxX,
              getTitlesWidget: (value, meta) {
                final isStart = value.abs() < 0.01;
                final isEnd = (value - maxX).abs() < 0.01;
                if (!isStart && !isEnd) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                  child: Text(
                    isStart ? startLabel : endLabel,
                    style: QaText.caption,
                  ),
                );
              },
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: targetAmount,
              color: QaColors.textSecondary.withValues(alpha: 0.55),
              strokeWidth: 1,
              dashArray: const [4, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topLeft,
                padding: const EdgeInsets.only(left: 2, bottom: 2),
                style: QaText.caption,
                labelResolver: (_) => 'Meta',
              ),
            ),
          ],
        ),
        betweenBarsData: [
          BetweenBarsData(
            fromIndex: _optimistic,
            toIndex: _pessimistic,
            color: accent.withValues(alpha: 0.12),
          ),
        ],
        lineBarsData: [
          hidden(spots((p) => p.values[PlanScenario.optimistic]!)),
          hidden(spots((p) => p.values[PlanScenario.pessimistic]!)),
          LineChartBarData(
            spots: spots((p) => p.contributed),
            color: contributedColor.withValues(alpha: 0.6),
            barWidth: 1.4,
            dashArray: const [3, 3],
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: contributedColor.withValues(alpha: 0.10),
            ),
          ),
          LineChartBarData(
            spots: spots((p) => p.base),
            color: accent,
            barWidth: 2.4,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              checkToShowDot:
                  (spot, bar) => spot == bar.spots.last && progress >= 1,
              getDotPainter:
                  (spot, percent, bar, index) => FlDotCirclePainter(
                    radius: 3.5,
                    color: accent,
                    strokeWidth: 2,
                    strokeColor: QaColors.surfaceCard,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  /// La parte de la serie que ya se dibujó según [progress]: el último
  /// punto se interpola para que la línea avance fluida.
  List<FlSpot> _visible(List<FlSpot> all) {
    if (progress >= 1) return all;
    final limit = all.last.x * progress.clamp(0.0, 1.0);
    final out = <FlSpot>[all.first];
    for (var i = 1; i < all.length; i++) {
      final prev = all[i - 1];
      final cur = all[i];
      if (cur.x <= limit) {
        out.add(cur);
        continue;
      }
      final span = cur.x - prev.x;
      final t = span <= 0 ? 0.0 : (limit - prev.x) / span;
      if (t > 0) out.add(FlSpot(limit, prev.y + (cur.y - prev.y) * t));
      break;
    }
    return out;
  }
}
