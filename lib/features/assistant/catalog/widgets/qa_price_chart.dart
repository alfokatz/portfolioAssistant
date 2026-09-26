import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/services/price_chart_data_loader.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/shared/utils/provider_lookup.dart';

/// Gráfico de precio histórico estilo Quartz / Apple Stocks: línea suavizada
/// con gradiente a transparente debajo, sin ejes ni grilla, selector de
/// período y scrub táctil con tooltip.
///
/// Cambiar de período es puramente cliente — refetchea vía
/// [PriceChartDataLoader] (nunca vuelve a llamar a Porty) y cachea cada
/// rango ya visto durante la vida del widget.
///
/// Fallback: si el período INICIAL no tiene datos (el loader devuelve
/// `null`, sin importar la causa), la card muestra [fallback] — el
/// contenido de `QaTickerSnapshot`/`QaTickerMove` — en vez de un gráfico
/// vacío. Si falla un período elegido después, el gráfico queda en pie y
/// solo ese rango muestra "sin datos", para no hacer desaparecer un gráfico
/// que ya funcionaba por tocar un tab.
///
/// Reveal: [active]/[onFinished] con el mismo contrato que `RevealStep`.
/// El primer fetch arranca al montar (antes de que le toque el turno), así
/// que en el caso común los datos ya están cuando la card aparece.
class QaPriceChart extends StatefulWidget {
  const QaPriceChart({
    super.key,
    required this.ticker,
    required this.initialRange,
    required this.fallback,
    this.weightPct = 0,
    this.active = true,
    this.onFinished,
  });

  final String ticker;
  final PriceChartRange initialRange;
  final Widget fallback;
  final double weightPct;
  final bool active;
  final VoidCallback? onFinished;

  static const chartHeight = 150.0;

  @override
  State<QaPriceChart> createState() => _QaPriceChartState();
}

class _QaPriceChartState extends State<QaPriceChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw;
  late PriceChartRange _range;
  final Map<PriceChartRange, List<PriceCandle>?> _cache = {};
  final Set<PriceChartRange> _inFlight = {};
  PriceChartDataLoader? _loader;
  bool _initialized = false;
  bool _revealStarted = false;
  bool _finished = false;
  bool _showFallback = false;
  int? _scrubIndex;

  /// Última serie efectivamente dibujada — se sigue mostrando (atenuada)
  /// mientras carga un período nuevo, en vez de dejar un hueco.
  List<PriceCandle>? _displayed;

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange;
    _draw = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _loader = readProviderOrNull(context, priceChartDataLoaderProvider);
    _fetch(_range);
  }

  @override
  void didUpdateWidget(covariant QaPriceChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeStartReveal();
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  Future<void> _fetch(PriceChartRange range) async {
    if (_cache.containsKey(range) || !_inFlight.add(range)) return;
    List<PriceCandle>? candles;
    try {
      candles = await _loader?.load(widget.ticker, range);
    } catch (_) {
      candles = null; // Mismo camino que "sin datos".
    }
    if (!mounted) return;
    setState(() {
      _inFlight.remove(range);
      _cache[range] = candles;
      if (range == _range) _displayed = candles ?? _displayed;
      if (range == widget.initialRange && !_revealStarted && candles == null) {
        _showFallback = true;
      }
    });
    if (range == _range && _revealStarted && candles != null) _animateDraw();
    _maybeStartReveal();
  }

  /// Arranca la entrada cuando se cumplen ambas: le tocó el turno y el
  /// período inicial ya resolvió (con datos o con fallback).
  void _maybeStartReveal() {
    if (_revealStarted || !widget.active) return;
    if (!_cache.containsKey(widget.initialRange)) return;
    _revealStarted = true;
    if (_showFallback) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
      return;
    }
    _animateDraw(onDone: _finish);
  }

  void _animateDraw({VoidCallback? onDone}) {
    if (_reduceMotion) {
      _draw.value = 1;
      if (onDone != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onDone());
      }
      return;
    }
    _draw.forward(from: 0).whenCompleteOrCancel(() {
      if (mounted) onDone?.call();
    });
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    widget.onFinished?.call();
  }

  void _selectRange(PriceChartRange range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _scrubIndex = null;
      _displayed = _cache[range] ?? _displayed;
    });
    if (_cache[range] != null) {
      _animateDraw();
    } else {
      _fetch(range);
    }
  }

  void _updateScrub(double dx, double width, int count) {
    if (count < 2 || width <= 0) return;
    final index = ((dx / width) * (count - 1)).round().clamp(0, count - 1);
    if (index == _scrubIndex) return;
    setState(() => _scrubIndex = index);
    PortyHapticsService.maybeOf(context)?.scrubTick();
  }

  void _endScrub() {
    if (_scrubIndex != null) setState(() => _scrubIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    // Con `QaCardShell.staged` la card ya se pinta antes de su turno: el
    // contenido queda invisible (con su espacio reservado) hasta `active`.
    return AnimatedOpacity(
      opacity: widget.active ? 1 : 0,
      duration:
          _reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
      child: _showFallback ? widget.fallback : _buildChart(),
    );
  }

  Widget _buildChart() {
    final candles = _cache[_range];
    final loading = _inFlight.contains(_range);
    final shown = candles ?? (loading ? _displayed : null);

    final isUp = shown == null || shown.last.close >= shown.first.close;
    final color = isUp ? PortfolioColors.profit : PortfolioColors.loss;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(
          ticker: widget.ticker,
          weightPct: widget.weightPct,
          candles: shown,
          range: _range,
          scrubIndex: _scrubIndex,
          color: color,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 30,
          child:
              candles != null && _scrubIndex != null
                  ? _ScrubTooltip(
                    candle: candles[_scrubIndex!],
                    fraction: _scrubIndex! / (candles.length - 1),
                    range: _range,
                  )
                  : null,
        ),
        SizedBox(
          height: QaPriceChart.chartHeight,
          width: double.infinity,
          child: _buildChartArea(shown, loading, color),
        ),
        const SizedBox(height: 10),
        _RangeSelector(selected: _range, onSelected: _selectRange),
      ],
    );
  }

  Widget _buildChartArea(List<PriceCandle>? shown, bool loading, Color color) {
    if (shown == null) {
      if (loading || !_cache.containsKey(_range)) {
        return const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: PortfolioColors.textSecondary,
            ),
          ),
        );
      }
      return const Center(
        child: Text(
          'Sin datos para este período',
          style: TextStyle(color: PortfolioColors.textSecondary, fontSize: 12),
        ),
      );
    }

    final closes = [for (final c in shown) c.close];
    final chart = AnimatedBuilder(
      animation: _draw,
      builder:
          (context, _) => CustomPaint(
            size: Size.infinite,
            painter: PriceLinePainter(
              values: closes,
              color: color,
              progress: Curves.easeOutCubic.transform(_draw.value),
              scrubIndex: loading ? null : _scrubIndex,
            ),
          ),
    );

    return Semantics(
      label: 'Gráfico de precio de ${widget.ticker}, ${_range.label}',
      child: AnimatedOpacity(
        opacity: loading ? 0.35 : 1,
        duration: const Duration(milliseconds: 150),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            if (loading) return chart;
            void update(Offset p) => _updateScrub(p.dx, width, closes.length);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) => update(d.localPosition),
              onHorizontalDragUpdate: (d) => update(d.localPosition),
              onHorizontalDragEnd: (_) => _endScrub(),
              onHorizontalDragCancel: _endScrub,
              onLongPressStart: (d) => update(d.localPosition),
              onLongPressMoveUpdate: (d) => update(d.localPosition),
              onLongPressEnd: (_) => _endScrub(),
              onLongPressCancel: _endScrub,
              child: chart,
            );
          },
        ),
      ),
    );
  }
}

final _currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

const _monthsEs = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

String _formatDate(DateTime date, PriceChartRange range) {
  if (range == PriceChartRange.day) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
  return '${date.day} ${_monthsEs[date.month - 1]} ${date.year}';
}

String _rangeSummaryLabel(PriceChartRange range) => switch (range) {
  PriceChartRange.day => 'Hoy',
  PriceChartRange.week => 'Última semana',
  PriceChartRange.month => 'Último mes',
  PriceChartRange.quarter => 'Últimos 3 meses',
  PriceChartRange.year => 'Último año',
  PriceChartRange.all => 'Todo el histórico',
};

/// Ticker + precio + variación. Sin scrub: resumen del rango completo
/// (último precio y variación total). Durante el scrub: precio del punto
/// y variación desde el inicio del rango hasta ese punto.
class _Header extends StatelessWidget {
  const _Header({
    required this.ticker,
    required this.weightPct,
    required this.candles,
    required this.range,
    required this.scrubIndex,
    required this.color,
  });

  final String ticker;
  final double weightPct;
  final List<PriceCandle>? candles;
  final PriceChartRange range;
  final int? scrubIndex;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final candles = this.candles;
    final point =
        candles == null ? null : candles[scrubIndex ?? candles.length - 1];
    final start = candles?.first.close;
    final changeAbs =
        point != null && start != null ? point.close - start : 0.0;
    final changePct =
        start != null && start != 0 ? changeAbs / start * 100 : 0.0;
    final sign = changeAbs >= 0 ? '+' : '-';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              ticker,
              style: const TextStyle(
                color: PortfolioColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (weightPct > 0)
              Text(
                '${weightPct.toStringAsFixed(1)}% del portfolio',
                style: const TextStyle(
                  color: PortfolioColors.textSecondary,
                  fontSize: 11,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          point == null ? '—' : _currency.format(point.close),
          style: const TextStyle(
            color: PortfolioColors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text:
                    point == null
                        ? ' '
                        : '$sign${_currency.format(changeAbs.abs())} '
                            '($sign${changePct.abs().toStringAsFixed(2)}%)',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
              TextSpan(
                text:
                    point == null
                        ? ''
                        : scrubIndex != null
                        ? '  desde el inicio'
                        : '  ${_rangeSummaryLabel(range)}',
                style: const TextStyle(color: PortfolioColors.textSecondary),
              ),
            ],
          ),
          style: const TextStyle(
            fontSize: 13,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Tooltip con precio y fecha exactos del punto scrubeado. Se alinea por
/// la misma fracción horizontal que el punto: `Alignment(-1 + 2f, 0)`
/// centra el tooltip sobre el dedo en el medio y lo mantiene dentro de la
/// card en los bordes, sin medir su ancho.
class _ScrubTooltip extends StatelessWidget {
  const _ScrubTooltip({
    required this.candle,
    required this.fraction,
    required this.range,
  });

  final PriceCandle candle;
  final double fraction;
  final PriceChartRange range;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment(-1 + 2 * fraction, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: PortfolioColors.surfaceElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: PortfolioColors.border),
        ),
        child: Text(
          '${_currency.format(candle.close)} · '
          '${_formatDate(candle.date, range)}',
          style: const TextStyle(
            color: PortfolioColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.selected, required this.onSelected});

  final PriceChartRange selected;
  final ValueChanged<PriceChartRange> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final range in PriceChartRange.values)
          Expanded(
            child: Semantics(
              button: true,
              selected: range == selected,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(range),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        range == selected
                            ? PortfolioColors.surfaceElevated
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    range.label,
                    style: TextStyle(
                      color:
                          range == selected
                              ? PortfolioColors.textPrimary
                              : PortfolioColors.textSecondary,
                      fontSize: 12,
                      fontWeight:
                          range == selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Línea de precio suavizada con interpolación cúbica monótona
/// (Fritsch–Carlson): a diferencia de Catmull-Rom no "sobrepasa" los
/// máximos/mínimos reales, así la curva nunca muestra un precio que no
/// existió. Debajo, un gradiente del color de la línea a transparente. Sin
/// ejes ni grilla. [progress] (0–1) revela la línea de izquierda a derecha.
class PriceLinePainter extends CustomPainter {
  PriceLinePainter({
    required this.values,
    required this.color,
    this.progress = 1,
    this.scrubIndex,
  });

  final List<double> values;
  final Color color;
  final double progress;
  final int? scrubIndex;

  static const _verticalPadding = 0.08;

  List<Offset> _points(Size size) {
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = maxV - minV;
    final top = size.height * _verticalPadding;
    final usable = size.height * (1 - 2 * _verticalPadding);
    final dx = size.width / (values.length - 1);
    return [
      for (var i = 0; i < values.length; i++)
        Offset(
          i * dx,
          span == 0
              ? size.height / 2
              : top + (1 - (values[i] - minV) / span) * usable,
        ),
    ];
  }

  /// Tangentes Fritsch–Carlson para puntos equiespaciados en x.
  static List<double> _tangents(List<Offset> p) {
    final n = p.length;
    final dx = p[1].dx - p[0].dx;
    final delta = [
      for (var i = 0; i < n - 1; i++) (p[i + 1].dy - p[i].dy) / dx,
    ];
    final m = List<double>.filled(n, 0);
    m[0] = delta.first;
    m[n - 1] = delta.last;
    for (var i = 1; i < n - 1; i++) {
      m[i] = delta[i - 1] * delta[i] <= 0 ? 0 : (delta[i - 1] + delta[i]) / 2;
    }
    for (var i = 0; i < n - 1; i++) {
      if (delta[i] == 0) {
        m[i] = 0;
        m[i + 1] = 0;
        continue;
      }
      final a = m[i] / delta[i];
      final b = m[i + 1] / delta[i];
      final s = a * a + b * b;
      if (s > 9) {
        final t = 3 / math.sqrt(s);
        m[i] = t * a * delta[i];
        m[i + 1] = t * b * delta[i];
      }
    }
    return m;
  }

  static Path smoothPath(List<Offset> p) {
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    if (p.length == 2) return path..lineTo(p.last.dx, p.last.dy);
    final m = _tangents(p);
    final third = (p[1].dx - p[0].dx) / 3;
    for (var i = 0; i < p.length - 1; i++) {
      path.cubicTo(
        p[i].dx + third,
        p[i].dy + m[i] * third,
        p[i + 1].dx - third,
        p[i + 1].dy - m[i + 1] * third,
        p[i + 1].dx,
        p[i + 1].dy,
      );
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.isEmpty) return;
    final points = _points(size);
    final line = smoothPath(points);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));

    final fill =
        Path.from(line)
          ..lineTo(points.last.dx, size.height)
          ..lineTo(points.first.dx, size.height)
          ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    final index = scrubIndex;
    if (index != null && index >= 0 && index < points.length) {
      final p = points[index];
      canvas.drawLine(
        Offset(p.dx, 0),
        Offset(p.dx, size.height),
        Paint()
          ..color = PortfolioColors.textSecondary.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(p, 5.5, Paint()..color = PortfolioColors.surfaceCard);
      canvas.drawCircle(p, 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(PriceLinePainter old) =>
      old.color != color ||
      old.progress != progress ||
      old.scrubIndex != scrubIndex ||
      !_sameValues(old.values, values);

  static bool _sameValues(List<double> a, List<double> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
