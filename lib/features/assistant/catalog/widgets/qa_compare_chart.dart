import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_market_parts.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_price_chart.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/services/price_chart_data_loader.dart';
import 'package:portfolio_assistant/shared/utils/provider_lookup.dart';

/// Serie alineada de un comparativo: fechas comunes a todos los tickers
/// con datos y, por ticker, el % de variación desde el primer punto.
@immutable
class CompareSeries {
  const CompareSeries({
    required this.dates,
    required this.pctByTicker,
    required this.missing,
  });

  final List<DateTime> dates;

  /// Solo tickers con datos, en el orden original.
  final Map<String, List<double>> pctByTicker;

  /// Tickers que no trajeron datos (o no se pudieron alinear).
  final Set<String> missing;

  int get length => dates.length;

  /// Alinea las velas por DÍA (dos tickers de la misma bolsa comparten
  /// ruedas; si uno cotiza en otra plaza, se quedan los días en común) y
  /// normaliza cada una a % desde el inicio del rango, para que tickers de
  /// $30 y de $900 se comparen en la misma escala.
  ///
  /// `null` si ningún ticker quedó con al menos 2 puntos.
  static CompareSeries? align(
    List<String> tickers,
    Map<String, List<PriceCandle>?> candles,
  ) {
    String key(DateTime d) => '${d.year}-${d.month}-${d.day}';
    final byDay = <String, Map<String, PriceCandle>>{};
    for (final t in tickers) {
      final list = candles[t];
      if (list == null || list.length < 2) continue;
      byDay[t] = {for (final c in list) key(c.date): c};
    }
    if (byDay.isEmpty) return null;

    var usable = byDay.keys.toList();
    var common = _intersect(usable.map((t) => byDay[t]!.keys.toSet()));
    if (common.length < 2) {
      // Sin días en común: mejor un ticker bien dibujado que nada.
      usable.sort((a, b) => byDay[b]!.length.compareTo(byDay[a]!.length));
      usable = [usable.first];
      common = byDay[usable.first]!.keys.toSet();
    }

    final reference = byDay[usable.first]!;
    final days =
        common.toList()
          ..sort((a, b) => reference[a]!.date.compareTo(reference[b]!.date));
    final pct = <String, List<double>>{};
    for (final t in tickers) {
      if (!usable.contains(t)) continue;
      final base = byDay[t]![days.first]!.close;
      if (base == 0) continue;
      pct[t] = [for (final d in days) (byDay[t]![d]!.close / base - 1) * 100];
    }
    if (pct.isEmpty) return null;
    return CompareSeries(
      dates: [for (final d in days) reference[d]!.date],
      pctByTicker: pct,
      missing: {
        for (final t in tickers)
          if (!pct.containsKey(t)) t,
      },
    );
  }

  static Set<String> _intersect(Iterable<Set<String>> sets) {
    final list = sets.toList();
    return list.skip(1).fold(list.first, (acc, s) => acc.intersection(s));
  }
}

/// Rendimiento comparado de 2–3 tickers en un período: una línea por
/// ticker normalizada a % desde el inicio del rango (todas arrancan en 0),
/// leyenda con el % final de cada uno, selector de período y scrub que
/// muestra el % de cada ticker en esa fecha.
///
/// Mismo contrato que [QaPriceChart]: datos del lado del cliente vía
/// [PriceChartDataLoader] (un request por ticker, cacheado por rango),
/// reveal con [active]/[onFinished], y [fallback] (los valores que mandó
/// el modelo) si en el período inicial NINGÚN ticker trae histórico. Si
/// falla solo uno, el gráfico sigue con los demás y la leyenda lo marca.
class QaCompareChart extends StatefulWidget {
  const QaCompareChart({
    super.key,
    required this.tickers,
    required this.initialRange,
    required this.fallback,
    this.active = true,
    this.onFinished,
  });

  final List<String> tickers;
  final PriceChartRange initialRange;
  final Widget fallback;
  final bool active;
  final VoidCallback? onFinished;

  /// 1D queda afuera: las velas intradía de distintos tickers no comparten
  /// timestamps. "Todo" tampoco: cada ticker tiene su propio origen.
  static const ranges = [
    PriceChartRange.week,
    PriceChartRange.month,
    PriceChartRange.quarter,
    PriceChartRange.year,
  ];

  static const chartHeight = 170.0;

  /// Normaliza un rango pedido a uno soportado por el comparativo.
  static PriceChartRange supportedRange(PriceChartRange range) =>
      switch (range) {
        PriceChartRange.day => PriceChartRange.week,
        PriceChartRange.all => PriceChartRange.year,
        _ => range,
      };

  @override
  State<QaCompareChart> createState() => _QaCompareChartState();
}

class _QaCompareChartState extends State<QaCompareChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw;
  late PriceChartRange _range;
  late final PriceChartRange _initialRange;
  final Map<PriceChartRange, CompareSeries?> _cache = {};
  final Set<PriceChartRange> _inFlight = {};
  PriceChartDataLoader? _loader;
  bool _initialized = false;
  bool _revealStarted = false;
  bool _finished = false;
  bool _showFallback = false;
  int? _scrubIndex;
  CompareSeries? _displayed;

  @override
  void initState() {
    super.initState();
    _initialRange = QaCompareChart.supportedRange(widget.initialRange);
    _range = _initialRange;
    _draw = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
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
  void didUpdateWidget(covariant QaCompareChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeStartReveal();
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  Future<List<PriceCandle>?> _loadOne(String ticker, PriceChartRange range) {
    final loader = _loader;
    if (loader == null) return Future.value(null);
    return loader.load(ticker, range).catchError((_) => null);
  }

  Future<void> _fetch(PriceChartRange range) async {
    if (_cache.containsKey(range) || !_inFlight.add(range)) return;
    final results = await Future.wait([
      for (final t in widget.tickers) _loadOne(t, range),
    ]);
    if (!mounted) return;
    final series = CompareSeries.align(widget.tickers, {
      for (var i = 0; i < widget.tickers.length; i++)
        widget.tickers[i]: results[i],
    });
    setState(() {
      _inFlight.remove(range);
      _cache[range] = series;
      if (range == _range) _displayed = series ?? _displayed;
      if (range == _initialRange && !_revealStarted && series == null) {
        _showFallback = true;
      }
    });
    if (range == _range && _revealStarted && series != null) _animateDraw();
    _maybeStartReveal();
  }

  void _maybeStartReveal() {
    if (_revealStarted || !widget.active) return;
    if (!_cache.containsKey(_initialRange)) return;
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
    return AnimatedOpacity(
      opacity: widget.active ? 1 : 0,
      duration:
          _reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
      child: _showFallback ? widget.fallback : _buildChart(),
    );
  }

  Widget _buildChart() {
    final series = _cache[_range];
    final loading = _inFlight.contains(_range);
    final shown = series ?? (loading ? _displayed : null);
    final scrub = series == null ? null : _scrubIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CompareHeader(
          tickers: widget.tickers,
          subtitle: 'Rendimiento · ${QaMarketParts.rangeSummaryLabel(_range)}',
        ),
        const SizedBox(height: QaSpace.sectionGap),
        _Legend(tickers: widget.tickers, series: shown, scrubIndex: scrub),
        const SizedBox(height: 6),
        SizedBox(
          height: 26,
          child:
              series != null && scrub != null
                  ? Align(
                    alignment: Alignment(
                      -1 + 2 * scrub / (series.length - 1),
                      0,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: QaColors.textPrimary,
                        borderRadius: BorderRadius.circular(
                          QaSpace.chipRadius - 2,
                        ),
                      ),
                      child: Text(
                        QaMarketParts.formatDate(series.dates[scrub], _range),
                        style: QaText.valueSm.copyWith(
                          color: QaColors.surfaceCard,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  )
                  : null,
        ),
        SizedBox(
          height: QaCompareChart.chartHeight,
          width: double.infinity,
          child: _buildChartArea(shown, loading),
        ),
        const SizedBox(height: QaSpace.gap),
        QaRangeTabs(
          ranges: QaCompareChart.ranges,
          selected: _range,
          onSelected: _selectRange,
        ),
        QaFollowUpBar(items: compareFollowUps(widget.tickers)),
      ],
    );
  }

  Widget _buildChartArea(CompareSeries? shown, bool loading) {
    if (shown == null) {
      if (loading || !_cache.containsKey(_range)) {
        return const QaChartSkeleton();
      }
      return Center(
        child: Text('Sin datos para este período', style: QaText.label),
      );
    }

    final lines = [
      for (var i = 0; i < widget.tickers.length; i++)
        if (shown.pctByTicker[widget.tickers[i]] case final values?)
          CompareLine(values: values, color: QaPalette.series(i)),
    ];
    final chart = AnimatedBuilder(
      animation: _draw,
      builder:
          (context, _) => CustomPaint(
            size: Size.infinite,
            painter: CompareLinePainter(
              lines: lines,
              labelStyle: DefaultTextStyle.of(
                context,
              ).style.merge(QaText.caption),
              progress: Curves.easeOutCubic.transform(_draw.value),
              scrubIndex: loading ? null : _scrubIndex,
            ),
          ),
    );

    return Semantics(
      label:
          'Gráfico comparado de ${widget.tickers.join(', ')}, ${_range.label}',
      child: AnimatedOpacity(
        opacity: loading ? 0.35 : 1,
        duration: const Duration(milliseconds: 150),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            if (loading) return chart;
            void update(Offset p) => _updateScrub(p.dx, width, shown.length);
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

/// Follow-ups de una comparación: noticias de los dos primeros y los
/// fundamentals del primero (lo natural después de "¿cuál rindió más?").
List<QaFollowUp> compareFollowUps(List<String> tickers) => [
  for (final t in tickers.take(2))
    QaFollowUp(
      'Noticias de $t',
      '¿Qué noticias hay de $t?',
      icon: Icons.article_outlined,
      feature: PlanFeature.news,
      ticker: t,
    ),
  if (tickers.isNotEmpty)
    QaFollowUp(
      'Fundamentals de ${tickers.first}',
      'Pasame los fundamentals de ${tickers.first}',
      icon: Icons.analytics_outlined,
      feature: PlanFeature.fundamentals,
      ticker: tickers.first,
    ),
];

/// Avatares superpuestos + "AAPL vs MSFT" + subtítulo: la identidad de
/// una card que compara tickers.
class CompareHeader extends StatelessWidget {
  const CompareHeader({super.key, required this.tickers, this.subtitle});

  final List<String> tickers;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    const size = 32.0;
    const overlap = 12.0;
    final shown = tickers.take(3).toList();
    final stackWidth =
        shown.isEmpty ? 0.0 : size + (shown.length - 1) * (size - overlap);
    return Row(
      children: [
        SizedBox(
          width: stackWidth,
          height: size,
          child: Stack(
            children: [
              for (var i = shown.length - 1; i >= 0; i--)
                Positioned(
                  left: i * (size - overlap),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: QaColors.surfaceCard,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(1.5),
                      child: QaTickerAvatar(ticker: shown[i], size: size - 3),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                shown.join(' vs '),
                style: QaText.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: QaText.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Una celda de leyenda por ticker: marca de color de su línea + ticker +
/// % al final del rango (o en el punto scrubeado). Tocarla pregunta por el
/// ticker.
class _Legend extends StatelessWidget {
  const _Legend({
    required this.tickers,
    required this.series,
    required this.scrubIndex,
  });

  final List<String> tickers;
  final CompareSeries? series;
  final int? scrubIndex;

  @override
  Widget build(BuildContext context) {
    final series = this.series;
    // El que va adelante en el punto mostrado, para un énfasis sutil.
    String? leader;
    var best = double.negativeInfinity;
    if (series != null && series.pctByTicker.length > 1) {
      for (final e in series.pctByTicker.entries) {
        final v = e.value[scrubIndex ?? e.value.length - 1];
        if (v > best) {
          best = v;
          leader = e.key;
        }
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < tickers.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: QaTappable(
              question: '¿Cómo viene ${tickers[i]}?',
              child: _LegendCell(
                ticker: tickers[i],
                color: QaPalette.series(i),
                value: switch (series?.pctByTicker[tickers[i]]) {
                  final v? => v[scrubIndex ?? v.length - 1],
                  null => null,
                },
                loaded: series != null,
                leading: leader == tickers[i],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _LegendCell extends StatelessWidget {
  const _LegendCell({
    required this.ticker,
    required this.color,
    required this.value,
    required this.loaded,
    required this.leading,
  });

  final String ticker;
  final Color color;
  final double? value;
  final bool loaded;
  final bool leading;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
      decoration: BoxDecoration(
        color: leading ? QaPalette.inset : Colors.transparent,
        borderRadius: BorderRadius.circular(QaSpace.insetRadius),
        border: Border.all(
          color: leading ? Colors.transparent : QaColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 3,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              QaTickerAvatar(ticker: ticker, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  ticker,
                  style: QaText.valueSm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 24,
            child: Align(
              alignment: Alignment.centerLeft,
              child:
                  value != null
                      ? QaDeltaChip(value: value)
                      : Text(loaded ? 'Sin datos' : '—', style: QaText.caption),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una línea del comparativo.
@immutable
class CompareLine {
  const CompareLine({required this.values, required this.color});
  final List<double> values;
  final Color color;
}

/// Líneas de % acumulado sobre una escala común, con el 0% como
/// referencia punteada (todas arrancan ahí). Misma curva monótona que
/// [PriceLinePainter] — nunca inventa un máximo que no existió.
class CompareLinePainter extends CustomPainter {
  CompareLinePainter({
    required this.lines,
    this.progress = 1,
    this.scrubIndex,
    TextStyle? labelStyle,
  }) : labelStyle = labelStyle ?? QaText.caption;

  final List<CompareLine> lines;

  /// Estilo heredado del contexto (el painter no ve el theme).
  final TextStyle labelStyle;
  final double progress;
  final int? scrubIndex;

  static const _pad = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final drawable = [
      for (final l in lines)
        if (l.values.length >= 2) l,
    ];
    if (drawable.isEmpty || size.isEmpty) return;

    var minV = 0.0;
    var maxV = 0.0;
    for (final l in drawable) {
      minV = math.min(minV, l.values.reduce(math.min));
      maxV = math.max(maxV, l.values.reduce(math.max));
    }
    final span = maxV - minV == 0 ? 1.0 : maxV - minV;
    final usable = size.height - 2 * _pad;
    double yOf(double v) => _pad + (1 - (v - minV) / span) * usable;

    final zeroY = yOf(0);
    paintDashedHorizontal(
      canvas,
      y: zeroY,
      width: size.width,
      color: QaColors.textSecondary.withValues(alpha: 0.35),
    );
    final zeroLabel = TextPainter(
      text: TextSpan(text: '0%', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    zeroLabel.paint(
      canvas,
      Offset(
        0,
        (zeroY - zeroLabel.height - 2).clamp(
          0.0,
          size.height - zeroLabel.height,
        ),
      ),
    );

    final allPoints = <List<Offset>>[];
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
    for (final l in drawable) {
      final dx = size.width / (l.values.length - 1);
      final points = [
        for (var i = 0; i < l.values.length; i++)
          Offset(i * dx, yOf(l.values[i])),
      ];
      allPoints.add(points);
      canvas.drawPath(
        PriceLinePainter.smoothPath(points),
        Paint()
          ..color = l.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();

    final index = scrubIndex;
    if (index == null) {
      if (progress < 1) return;
      // Punto final de cada línea: dónde terminó cada uno.
      for (var k = 0; k < drawable.length; k++) {
        final p = allPoints[k].last;
        canvas.drawCircle(p, 4.5, Paint()..color = QaColors.surfaceCard);
        canvas.drawCircle(p, 3, Paint()..color = drawable[k].color);
      }
      return;
    }
    final first = allPoints.first;
    if (index < 0 || index >= first.length) return;
    canvas.drawLine(
      Offset(first[index].dx, 0),
      Offset(first[index].dx, size.height),
      Paint()
        ..color = QaColors.textSecondary.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
    for (var k = 0; k < drawable.length; k++) {
      if (index >= allPoints[k].length) continue;
      final p = allPoints[k][index];
      canvas.drawCircle(p, 5.5, Paint()..color = QaColors.surfaceCard);
      canvas.drawCircle(p, 4, Paint()..color = drawable[k].color);
    }
  }

  @override
  bool shouldRepaint(CompareLinePainter old) =>
      old.progress != progress ||
      old.scrubIndex != scrubIndex ||
      !identical(old.lines, lines);
}
