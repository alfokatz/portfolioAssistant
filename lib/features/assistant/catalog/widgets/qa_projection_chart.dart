import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/shared/animation/reveal_animation.dart';

/// Un punto de la serie de proyección: `label` es el eje X (ej. "Ene 2027"),
/// `value` es el monto proyectado en ese punto.
class ProjectionChartPoint {
  const ProjectionChartPoint({required this.label, required this.value});

  final String label;
  final double value;
}

/// Chart de líneas para mostrar una proyección en el tiempo (ej. la
/// evolución proyectada de una meta financiera). Sin grilla ni ejes
/// laterales: una sola serie en el acento (la proyección es "la mirada de
/// Porty" hacia adelante, no un dato de mercado con signo), relleno en
/// gradiente a transparente y, si hay [targetAmount], la meta como línea
/// punteada — así se lee de un vistazo cuánto falta para cruzarla.
///
/// El "dibujo" progresivo no usa una API nativa de `fl_chart` (no expone
/// una) — se anima cuántos puntos de la serie están visibles, interpolando
/// el último entre los dos reales más cercanos para que la línea avance
/// fluida en vez de saltar punto a punto.
///
/// Reveal en dos fases, igual criterio que el resto del catálogo: primero
/// el encabezado (fade corto), después se dibuja la línea. [active] indica
/// si ya le toca el turno (ver `RevealStep`/`QaCardShell.staged`);
/// [onFinished] se llama una sola vez, al terminar ambas fases.
class QaProjectionChart extends StatefulWidget {
  const QaProjectionChart({
    super.key,
    required this.label,
    required this.points,
    this.targetAmount,
    this.active = true,
    this.onFinished,
  });

  final String label;
  final List<ProjectionChartPoint> points;

  /// Monto objetivo: se dibuja como línea punteada horizontal.
  final double? targetAmount;
  final bool active;
  final VoidCallback? onFinished;

  @override
  State<QaProjectionChart> createState() => _QaProjectionChartState();
}

class _QaProjectionChartState extends State<QaProjectionChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _labelOpacity;
  late final Animation<double> _drawProgress;
  bool _started = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addStatusListener(_handleStatus);
    _labelOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.2, curve: Curves.easeOutCubic),
    );
    _drawProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeStart();
  }

  @override
  void didUpdateWidget(covariant QaProjectionChart oldWidget) {
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
    // Sin al menos 2 puntos no hay una línea sensata que trazar — el
    // controller igual corre y llama onFinished normalmente, así la
    // secuencia general no queda trabada esperando a un chart vacío.
    if (widget.points.length < 2) return const SizedBox.shrink();

    final last = widget.points.last;
    final target = widget.targetAmount;
    final hasTarget = target != null && target > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: _labelOpacity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.label.isNotEmpty)
                Text(
                  widget.label,
                  style: QaText.label.copyWith(fontWeight: FontWeight.w600),
                ),
              const SizedBox(height: 6),
              Text(QaFormat.money(last.value), style: QaText.displaySm),
              const SizedBox(height: 2),
              Text(
                [
                  if (last.label.isNotEmpty) 'Proyectado a ${last.label}',
                  if (hasTarget) 'meta ${QaFormat.money(target)}',
                ].join(' · '),
                style: QaText.caption,
              ),
            ],
          ),
        ),
        const SizedBox(height: QaSpace.gap),
        SizedBox(
          height: 140,
          child: AnimatedBuilder(
            animation: _drawProgress,
            builder:
                (context, _) => _ProjectionLineChart(
                  points: widget.points,
                  targetAmount: hasTarget ? target : null,
                  progress: _drawProgress.value,
                ),
          ),
        ),
      ],
    );
  }
}

class _ProjectionLineChart extends StatelessWidget {
  const _ProjectionLineChart({
    required this.points,
    required this.progress,
    this.targetAmount,
  });

  final List<ProjectionChartPoint> points;
  final double progress;
  final double? targetAmount;

  static const _lineColor = PortfolioColors.accentBlue;

  @override
  Widget build(BuildContext context) {
    final values = [
      ...points.map((p) => p.value),
      if (targetAmount != null) targetAmount!,
    ];
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final span = (maxY - minY).abs();
    // Serie plana (todos los puntos iguales): sin un rango artificial el
    // chart colapsa a una línea pegada al borde.
    final pad = span < 1e-9 ? (maxY.abs() * 0.1 + 1) : span * 0.12;
    final target = targetAmount;

    return LineChart(
      duration: Duration.zero,
      LineChartData(
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: const FlGridData(show: false),
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
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if ((value - i).abs() > 0.01) return const SizedBox.shrink();
                final isEdge = i == 0 || i == points.length - 1;
                if (i < 0 || i >= points.length || !isEdge) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                  child: Text(points[i].label, style: QaText.caption),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (target != null)
              HorizontalLine(
                y: target,
                color: PortfolioColors.textSecondary.withValues(alpha: 0.55),
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
        lineBarsData: [
          LineChartBarData(
            spots: _visibleSpots(),
            isCurved: false,
            color: _lineColor,
            barWidth: 2.2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              // Solo el punto de la "punta" de la línea: marca hasta dónde
              // llegó el dibujo y, al final, el monto proyectado.
              checkToShowDot:
                  (spot, bar) => spot == bar.spots.last && progress >= 1,
              getDotPainter:
                  (spot, percent, bar, index) => FlDotCirclePainter(
                    radius: 3.5,
                    color: _lineColor,
                    strokeWidth: 2,
                    strokeColor: PortfolioColors.surfaceCard,
                  ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _lineColor.withValues(alpha: 0.22),
                  _lineColor.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Cuántos puntos van visibles según [progress] (0..1) — el último punto
  /// se interpola entre los dos reales más cercanos para un avance fluido.
  List<FlSpot> _visibleSpots() {
    final totalSegments = points.length - 1;
    final exactIndex = (progress.clamp(0.0, 1.0)) * totalSegments;
    final fullIndex = exactIndex.floor().clamp(0, totalSegments);
    final spots = <FlSpot>[
      for (var i = 0; i <= fullIndex; i++)
        FlSpot(i.toDouble(), points[i].value),
    ];
    if (fullIndex < totalSegments) {
      final t = exactIndex - fullIndex;
      final from = points[fullIndex].value;
      final to = points[fullIndex + 1].value;
      spots.add(FlSpot(fullIndex + t, from + (to - from) * t));
    }
    return spots;
  }
}
