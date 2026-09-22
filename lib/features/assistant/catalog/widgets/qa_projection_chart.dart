import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Un punto de la serie de proyección: `label` es el eje X (ej. "Ene 2027"),
/// `value` es el monto proyectado en ese punto.
class ProjectionChartPoint {
  const ProjectionChartPoint({required this.label, required this.value});

  final String label;
  final double value;
}

/// Chart de líneas para mostrar una proyección en el tiempo (ej. la
/// evolución proyectada de una meta financiera). Estilo "Quiet Ledger": una
/// sola serie, sin relleno de área, sin sombra ni gradiente — el trazo usa
/// `PortfolioColors.chartLine` (charcoal), no el acento terracota (que se
/// reserva para foco/marca IA, no para el chart en sí).
///
/// El "dibujo" progresivo no usa una API nativa de `fl_chart` (no expone
/// una) — se anima cuántos puntos de la serie están visibles, interpolando
/// el último entre los dos reales más cercanos para que la línea avance
/// fluida en vez de saltar punto a punto.
///
/// Reveal en dos fases, igual criterio que el resto del catálogo: primero
/// el label (fade corto), después se dibuja la línea. [active] indica si ya
/// le toca el turno (ver `RevealStep`/`QaCardShell.staged`); [onFinished] se
/// llama una sola vez, al terminar ambas fases.
class QaProjectionChart extends StatefulWidget {
  const QaProjectionChart({
    super.key,
    required this.label,
    required this.points,
    this.active = true,
    this.onFinished,
  });

  final String label;
  final List<ProjectionChartPoint> points;
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
      duration: const Duration(milliseconds: 700),
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
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: _labelOpacity,
          child: Text(
            widget.label,
            style: const TextStyle(
              color: PortfolioColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 120,
          child: AnimatedBuilder(
            animation: _drawProgress,
            builder:
                (context, _) => _ProjectionLineChart(
                  points: widget.points,
                  progress: _drawProgress.value,
                ),
          ),
        ),
      ],
    );
  }
}

class _ProjectionLineChart extends StatelessWidget {
  const _ProjectionLineChart({required this.points, required this.progress});

  final List<ProjectionChartPoint> points;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final values = points.map((p) => p.value).toList();
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY).abs() * 0.12;

    return LineChart(
      duration: Duration.zero,
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine:
              (_) => const FlLine(
                color: PortfolioColors.chartGrid,
                strokeWidth: 1,
              ),
        ),
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
              getTitlesWidget: (value, meta) {
                final i = value.round();
                final isEdge = i == 0 || i == points.length - 1;
                if (i < 0 || i >= points.length || !isEdge) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    points[i].label,
                    style: const TextStyle(
                      color: PortfolioColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: _visibleSpots(),
            isCurved: false,
            color: PortfolioColors.chartLine,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
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
      for (var i = 0; i <= fullIndex; i++) FlSpot(i.toDouble(), points[i].value),
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
