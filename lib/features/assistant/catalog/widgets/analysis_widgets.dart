import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_time.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/assistant/data/analysis/company_analysis_data.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/profile_candidate_matcher.dart';
import 'package:portfolio_assistant/features/assistant/services/price_chart_data_loader.dart';
import 'package:portfolio_assistant/features/assistant/utils/analysis_prose_check.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/pnl_badge.dart';
import 'package:portfolio_assistant/shared/utils/provider_lookup.dart';
import 'package:url_launcher/url_launcher.dart';

/// Análisis de una empresa para un inversor casual: una sola card, leída de
/// arriba a abajo en ~20 segundos.
///
/// División del trabajo (la decisión central del widget):
/// - el MODELO escribe solo el texto — el resumen, los puntos clave con su
///   tono, qué métricas destacar y cómo explicarlas, el tono de las noticias;
/// - la APP pone todos los números — precio, variación, métricas, rango de
///   52 semanas, resultados, titulares, riesgo y la fila de cartera — desde
///   los resultados de tools del turno ([QaEvidenceScope]).
/// Así ningún número de la card puede ser inventado, y lo que el modelo
/// escribe se filtra igual contra esos datos ([AnalysisProseCheck]).
abstract final class AnalysisWidgets {
  static Widget qaCompanyAnalysis(CatalogItemContext ctx) {
    final prose = _AnalysisProse.fromMap(ctx.data as JsonMap);
    return Builder(
      builder: (context) {
        final data = CompanyAnalysisData.from(
          QaEvidenceScope.of(context, ctx.surfaceId),
          prose.ticker,
        );
        return QaCardShell.staged(
          staged:
              (context, active, onFinished) => _AnalysisBody(
                prose: prose.cleaned(data.backingNumbers.toList()),
                data: data,
                active: active,
                onFinished: onFinished,
              ),
        );
      },
    );
  }
}

/// Métricas que el modelo puede destacar, con el rótulo, el formato y una
/// explicación por defecto (sin números) por si no escribe la suya.
enum AnalysisMetric {
  peTtm(
    'pe_ttm',
    'P/E',
    AnalysisMetricUnit.times,
    'Cuántos años de ganancias actuales pagás al comprar la acción.',
  ),
  forwardPe(
    'forward_pe',
    'P/E proyectado',
    AnalysisMetricUnit.times,
    'Lo mismo, con las ganancias que se esperan para el próximo año.',
  ),
  pb(
    'pb',
    'Precio / valor libros',
    AnalysisMetricUnit.times,
    'Cuánto pagás por cada dólar de patrimonio de la empresa.',
  ),
  psTtm(
    'ps_ttm',
    'Precio / ventas',
    AnalysisMetricUnit.times,
    'Cuánto pagás por cada dólar que la empresa vende en un año.',
  ),
  pegTtm(
    'peg_ttm',
    'PEG',
    AnalysisMetricUnit.times,
    'El P/E ajustado por lo rápido que crecen sus ganancias.',
  ),
  evEbitda(
    'ev_ebitda_ttm',
    'EV / EBITDA',
    AnalysisMetricUnit.times,
    'Lo que vale el negocio entero frente a lo que genera por año.',
  ),
  roeTtm(
    'roe_ttm',
    'ROE',
    AnalysisMetricUnit.percent,
    'Cuánto gana por cada dólar que pusieron sus accionistas.',
  ),
  roaTtm(
    'roa_ttm',
    'ROA',
    AnalysisMetricUnit.percent,
    'Cuánto gana por cada dólar de activos que maneja.',
  ),
  grossMargin(
    'gross_margin_ttm',
    'Margen bruto',
    AnalysisMetricUnit.percent,
    'Lo que queda de cada venta después del costo directo.',
  ),
  operatingMargin(
    'operating_margin_ttm',
    'Margen operativo',
    AnalysisMetricUnit.percent,
    'Lo que queda de cada venta después de operar el negocio.',
  ),
  netMargin(
    'net_margin_ttm',
    'Margen neto',
    AnalysisMetricUnit.percent,
    'Lo que queda de cada venta después de todos los gastos.',
  ),
  epsGrowth(
    'eps_growth_ttm_yoy',
    'Crecimiento de ganancias',
    AnalysisMetricUnit.percent,
    'Cuánto crecieron sus ganancias por acción en el último año.',
  ),
  dividendYield(
    'dividend_yield_indicated_annual',
    'Dividendo',
    AnalysisMetricUnit.percent,
    'Lo que paga por año en dividendos, sobre el precio de la acción.',
  ),
  payout(
    'payout_ratio_ttm',
    'Payout',
    AnalysisMetricUnit.percent,
    'Qué parte de sus ganancias reparte como dividendo.',
  ),
  marketCap(
    'market_capitalization',
    'Valor de mercado',
    AnalysisMetricUnit.millions,
    'Lo que vale la empresa entera en la bolsa.',
  );

  const AnalysisMetric(this.key, this.label, this.unit, this.fallback);

  final String key;
  final String label;
  final AnalysisMetricUnit unit;
  final String fallback;

  static AnalysisMetric? byKey(String key) {
    for (final m in values) {
      if (m.key == key) return m;
    }
    return null;
  }

  /// Si el modelo no eligió ninguna: las 3 que mejor resumen valuación,
  /// rentabilidad e ingreso para alguien que no sigue balances.
  static const defaults = [peTtm, netMargin, roeTtm, dividendYield];

  String format(double v) => switch (unit) {
    AnalysisMetricUnit.times => '${_decimal(v, 1)}x',
    AnalysisMetricUnit.percent => '${_decimal(v, 1)}%',
    AnalysisMetricUnit.millions => QaFormat.moneyCompact(v * 1e6),
  };
}

enum AnalysisMetricUnit { times, percent, millions }

String _decimal(double v, int digits) =>
    v.toStringAsFixed(digits).replaceAll('.', ',');

enum _Tone { strength, neutral, watch }

class _KeyPoint {
  const _KeyPoint(this.tone, this.text);
  final _Tone tone;
  final String text;
}

class _MetricPick {
  const _MetricPick(this.metric, this.explanation);
  final AnalysisMetric metric;
  final String explanation;
}

/// Lo que escribió el modelo, ya parseado.
class _AnalysisProse {
  const _AnalysisProse({
    required this.ticker,
    required this.summary,
    required this.keyPoints,
    required this.metrics,
    required this.newsTake,
  });

  factory _AnalysisProse.fromMap(JsonMap map) {
    String str(Object? v) => v is String ? v.trim() : '';
    final points = <_KeyPoint>[];
    for (final raw in (map['keyPoints'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final text = str(raw['text']);
      if (text.isEmpty) continue;
      final tone = switch (raw['tone']) {
        'strength' => _Tone.strength,
        'watch' => _Tone.watch,
        _ => _Tone.neutral,
      };
      points.add(_KeyPoint(tone, text));
    }
    final metrics = <_MetricPick>[];
    for (final raw in (map['metrics'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final metric = AnalysisMetric.byKey(str(raw['key']));
      if (metric == null || metrics.any((m) => m.metric == metric)) continue;
      metrics.add(_MetricPick(metric, str(raw['explanation'])));
    }
    return _AnalysisProse(
      ticker: str(map['ticker']).toUpperCase(),
      summary: str(map['summary']),
      keyPoints: points.take(4).toList(),
      metrics: metrics.take(4).toList(),
      newsTake: str(map['newsTake']),
    );
  }

  final String ticker;
  final String summary;
  final List<_KeyPoint> keyPoints;
  final List<_MetricPick> metrics;
  final String newsTake;

  /// Segunda red (la primera es el chequeo del turno): cualquier oración
  /// con un número que no está en los datos, o con consejo de compra/venta,
  /// se saca antes de mostrarla.
  _AnalysisProse cleaned(List<double> backing) {
    String clean(String s) => AnalysisProseCheck.clean(s, backing);
    return _AnalysisProse(
      ticker: ticker,
      summary: clean(summary),
      keyPoints: [
        for (final p in keyPoints)
          if (clean(p.text) case final t when t.isNotEmpty)
            _KeyPoint(p.tone, t),
      ],
      metrics: [
        for (final m in metrics) _MetricPick(m.metric, clean(m.explanation)),
      ],
      newsTake: clean(newsTake),
    );
  }
}

class _AnalysisBody extends StatefulWidget {
  const _AnalysisBody({
    required this.prose,
    required this.data,
    required this.active,
    required this.onFinished,
  });

  final _AnalysisProse prose;
  final CompanyAnalysisData data;
  final bool active;
  final VoidCallback onFinished;

  @override
  State<_AnalysisBody> createState() => _AnalysisBodyState();
}

class _AnalysisBodyState extends State<_AnalysisBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
  }

  @override
  void didUpdateWidget(covariant _AnalysisBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeStart();
  }

  void _maybeStart() {
    if (_started || !widget.active || !mounted) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _entrance.value = 1;
      widget.onFinished();
      return;
    }
    _entrance.forward().whenComplete(() {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections();
    final children = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      if (i > 0 && sections[i].divided) {
        children.add(const QaDivider(vertical: 14));
      } else if (i > 0) {
        children.add(const SizedBox(height: QaSpace.gap));
      }
      children.add(
        _Staggered(
          animation: _entrance,
          index: i,
          count: sections.length,
          child: sections[i].child,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  List<({Widget child, bool divided})> _sections() {
    final d = widget.data;
    final p = widget.prose;
    final out = <({Widget child, bool divided})>[];
    void add(Widget? w, {bool divided = true}) {
      if (w != null) out.add((child: w, divided: divided));
    }

    add(_Header(data: d), divided: false);
    if (p.summary.isNotEmpty) add(_Summary(text: p.summary), divided: false);
    add(_KeyPoints.maybe(p.keyPoints));
    add(_Metrics.maybe(d, p.metrics));
    add(_PriceRange.maybe(d));
    add(_Results.maybe(d));
    add(_News.maybe(d, p.newsTake));
    add(_Risk.maybe(d));
    add(_Holding.maybe(d));
    add(const _Disclaimer());
    add(
      QaFollowUpBar(
        items:
            QaTickerFollowUps.of(
              d.ticker,
              exclude: {QaTickerFollowUps.analysis},
            ).take(3).toList(),
      ),
      divided: false,
    );
    return out;
  }
}

/// Entrada escalonada muy sutil dentro del reveal de la card: cada sección
/// aparece apenas después de la anterior (fade + 6px). Con animaciones
/// deshabilitadas el controller ya está en 1 y todo se ve de entrada.
class _Staggered extends StatelessWidget {
  const _Staggered({
    required this.animation,
    required this.index,
    required this.count,
    required this.child,
  });

  final Animation<double> animation;
  final int index;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final step = count <= 1 ? 0.0 : 0.5 / (count - 1);
    final start = (index * step).clamp(0.0, 0.5);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(start, start + 0.5, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: curved,
      builder:
          (context, child) => Opacity(
            opacity: curved.value,
            child: Transform.translate(
              offset: Offset(0, 6 * (1 - curved.value)),
              child: child,
            ),
          ),
      child: child,
    );
  }
}

// ── a) Encabezado ──────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.data});
  final CompanyAnalysisData data;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (data.companyName != null) data.companyName!,
      if (data.industry != null) data.industry!,
    ].join(' · ');
    final price = data.currentPrice;
    final change = data.periodChange;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QaTickerHeader(
          ticker: data.ticker,
          subtitle: subtitle.isEmpty ? null : subtitle,
          tapQuestion: '¿Cómo viene ${data.ticker}?',
        ),
        if (price != null) ...[
          const SizedBox(height: QaSpace.gap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(QaFormat.price(price), style: QaText.display),
              if (change != null) ...[
                const SizedBox(width: 10),
                PnlBadge(percent: change.pct),
                if (change.label.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      change.label,
                      style: QaText.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ],
      ],
    );
  }
}

// ── b) En resumen ─────────────────────────────────────────────────────────

class _Summary extends StatelessWidget {
  const _Summary({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        const QaSectionLabel('En resumen'),
        const SizedBox(height: 6),
        Text(text, style: QaText.body.copyWith(fontSize: 15, height: 1.45)),
      ],
    );
  }
}

// ── c) Puntos clave ───────────────────────────────────────────────────────

class _KeyPoints extends StatelessWidget {
  const _KeyPoints(this.points);
  final List<_KeyPoint> points;

  static Widget? maybe(List<_KeyPoint> points) =>
      points.isEmpty ? null : _KeyPoints(points);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const QaSectionLabel('Puntos clave'),
        const SizedBox(height: 8),
        for (var i = 0; i < points.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _KeyPointRow(point: points[i]),
        ],
      ],
    );
  }
}

class _KeyPointRow extends StatelessWidget {
  const _KeyPointRow({required this.point});
  final _KeyPoint point;

  @override
  Widget build(BuildContext context) {
    // Color semántico sutil: el ícono lleva el tono y el fondo es un tinte
    // del contenedor (nunca un color saturado de relleno).
    final (IconData icon, Color fg, Color bg, String semantics) = switch (point
        .tone) {
      _Tone.strength => (
        Icons.check_rounded,
        QaColors.profit,
        QaColors.profitContainer,
        'Fortaleza',
      ),
      _Tone.watch => (
        Icons.priority_high_rounded,
        QaColors.loss,
        QaColors.lossContainer,
        'A vigilar',
      ),
      _Tone.neutral => (
        Icons.remove_rounded,
        QaColors.textSecondary,
        QaPalette.track,
        'Neutral',
      ),
    };
    return Semantics(
      label: semantics,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, size: 13, color: fg),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(point.text, style: QaText.body)),
        ],
      ),
    );
  }
}

// ── Aviso de sección fuera del plan ───────────────────────────────────────

class _GoldNotice extends StatelessWidget {
  const _GoldNotice({required this.title, required this.what});

  final String title;
  final String what;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QaSectionLabel(title),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 15,
              color: QaColors.accentBlue,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                what,
                style: QaText.label.copyWith(color: QaColors.textPrimary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── d) Valuación y rentabilidad ───────────────────────────────────────────

class _Metrics extends StatelessWidget {
  const _Metrics(this.rows);
  final List<({AnalysisMetric metric, double value, String explanation})> rows;

  static Widget? maybe(CompanyAnalysisData d, List<_MetricPick> picks) {
    if (d.fundamentalsStatus == AnalysisSourceStatus.locked) {
      return const _GoldNotice(
        title: 'Valuación y rentabilidad',
        what: 'Incluido en el plan Gold',
      );
    }
    final chosen =
        picks.isNotEmpty
            ? picks
            : [for (final m in AnalysisMetric.defaults) _MetricPick(m, '')];
    final rows =
        <({AnalysisMetric metric, double value, String explanation})>[];
    for (final pick in chosen) {
      final value = d.metric(pick.metric.key);
      // Un dividendo en 0 no es un dato para destacar: la empresa no paga.
      if (value == null ||
          (pick.metric == AnalysisMetric.dividendYield && value <= 0)) {
        continue;
      }
      rows.add((
        metric: pick.metric,
        value: value,
        explanation:
            pick.explanation.isNotEmpty
                ? pick.explanation
                : pick.metric.fallback,
      ));
      if (rows.length == 4) break;
    }
    return rows.isEmpty ? null : _Metrics(rows);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const QaSectionLabel('Valuación y rentabilidad'),
        for (final row in rows) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(row.metric.label, style: QaText.bodyStrong)),
              Text(row.metric.format(row.value), style: QaText.value),
            ],
          ),
          const SizedBox(height: 2),
          Text(row.explanation, style: QaText.label),
        ],
      ],
    );
  }
}

// ── e) Precio: rango de 52 semanas + sparkline ────────────────────────────

class _PriceRange extends StatelessWidget {
  const _PriceRange({
    required this.ticker,
    required this.low,
    required this.high,
    required this.price,
  });

  final String ticker;
  final double low;
  final double high;
  final double price;

  static Widget? maybe(CompanyAnalysisData d) {
    final low = d.week52Low;
    final high = d.week52High;
    final price = d.currentPrice;
    if (low == null || high == null || price == null || high <= low) {
      return null;
    }
    return _PriceRange(ticker: d.ticker, low: low, high: high, price: price);
  }

  @override
  Widget build(BuildContext context) {
    final fromTop = ((high - math.min(price, high)) / high * 100);
    final caption =
        fromTop < 1
            ? 'Cerca de su máximo de 52 semanas'
            : 'A ${_decimal(fromTop, 1)}% de su máximo de 52 semanas';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QaSectionLabel('Precio', trailing: _MonthSparkline(ticker: ticker)),
        const SizedBox(height: 10),
        QaRangeBar(
          min: low,
          max: high,
          value: price,
          minLabel: 'Mín. 52 sem. ${QaFormat.price(low)}',
          maxLabel: 'Máx. ${QaFormat.price(high)}',
        ),
        const SizedBox(height: 6),
        Text(caption, style: QaText.label),
      ],
    );
  }
}

/// Sparkline chico del último mes, cargado del lado del cliente (la misma
/// serie del gráfico de precio). Si no hay datos, no ocupa lugar.
class _MonthSparkline extends StatefulWidget {
  const _MonthSparkline({required this.ticker});
  final String ticker;

  @override
  State<_MonthSparkline> createState() => _MonthSparklineState();
}

class _MonthSparklineState extends State<_MonthSparkline> {
  List<double>? _values;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    // Decorativo: si armar el provider falla, la sección sigue sin curva.
    final PriceChartDataLoader? loader;
    try {
      loader = readProviderOrNull(context, priceChartDataLoaderProvider);
    } catch (_) {
      return;
    }
    loader?.load(widget.ticker, PriceChartRange.month).then((candles) {
      if (!mounted || candles == null) return;
      setState(() => _values = [for (final c in candles) c.close]);
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final values = _values;
    if (values == null || values.length < 2) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('1 mes', style: QaText.caption),
        const SizedBox(width: 6),
        QaSparkline(values: values, width: 56, height: 18),
      ],
    );
  }
}

// ── f) Resultados ─────────────────────────────────────────────────────────

class _Results extends StatelessWidget {
  const _Results({this.latest, this.next});

  final Map<String, Object?>? latest;
  final Map<String, Object?>? next;

  static Widget? maybe(CompanyAnalysisData d) {
    if (d.earningsStatus == AnalysisSourceStatus.locked) {
      return const _GoldNotice(
        title: 'Resultados',
        what: 'Incluido en el plan Gold',
      );
    }
    final latest = d.latestResult;
    final next = d.nextReport;
    final hasLatest =
        latest != null &&
        latest['eps_actual'] is num &&
        latest['eps_estimate'] is num;
    final hasNext = next != null && '${next['date_label'] ?? ''}'.isNotEmpty;
    if (!hasLatest && !hasNext) return null;
    return _Results(
      latest: hasLatest ? latest : null,
      next: hasNext ? next : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = latest;
    final n = next;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const QaSectionLabel('Resultados'),
        if (l != null) ...[const SizedBox(height: 10), _LatestRow(result: l)],
        if (n != null) ...[const SizedBox(height: 10), _NextRow(report: n)],
      ],
    );
  }
}

class _LatestRow extends StatelessWidget {
  const _LatestRow({required this.result});
  final Map<String, Object?> result;

  @override
  Widget build(BuildContext context) {
    final actual = (result['eps_actual'] as num).toDouble();
    final estimate = (result['eps_estimate'] as num).toDouble();
    final beat =
        result['beat'] is bool ? result['beat'] as bool : actual >= estimate;
    final period = '${result['fiscal_period_label'] ?? ''}'.trim();
    final date = '${result['report_date_label'] ?? ''}'.trim();
    final when = [
      if (period.isNotEmpty) period,
      if (date.isNotEmpty) date,
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                when.isEmpty ? 'Último reporte' : 'Último reporte · $when',
                style: QaText.label,
              ),
              const SizedBox(height: 2),
              Text(
                'Ganó ${QaFormat.price(actual)} por acción; '
                'se esperaban ${QaFormat.price(estimate)}',
                style: QaText.body,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        QaTag(
          beat ? 'Superó' : 'No alcanzó',
          color: beat ? QaColors.profit : QaColors.loss,
        ),
      ],
    );
  }
}

class _NextRow extends StatelessWidget {
  const _NextRow({required this.report});
  final Map<String, Object?> report;

  @override
  Widget build(BuildContext context) {
    final label = '${report['date_label']}';
    final iso = DateTime.tryParse('${report['date'] ?? ''}');
    final countdown = iso == null ? null : QaTime.countdown(iso);
    final eps = report['eps_estimate'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Próximo reporte', style: QaText.label),
              const SizedBox(height: 2),
              Text(label, style: QaText.bodyStrong),
              if (eps is num)
                Text(
                  'Se espera que gane ${QaFormat.price(eps)} por acción',
                  style: QaText.label,
                ),
            ],
          ),
        ),
        if (countdown != null && countdown.isNotEmpty) ...[
          const SizedBox(width: 8),
          QaTag(countdown, icon: Icons.schedule_rounded),
        ],
      ],
    );
  }
}

// ── g) Noticias ───────────────────────────────────────────────────────────

class _News extends StatelessWidget {
  const _News({required this.items, required this.take});

  final List<Map<String, Object?>> items;
  final String take;

  static Widget? maybe(CompanyAnalysisData d, String take) {
    if (d.newsStatus == AnalysisSourceStatus.locked) {
      return const _GoldNotice(
        title: 'Noticias',
        what: 'Incluido en el plan Gold',
      );
    }
    if (d.news.isEmpty) return null;
    return _News(items: d.news.take(3).toList(), take: take);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const QaSectionLabel('Noticias'),
        if (take.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(take, style: QaText.body),
        ],
        for (final item in items) ...[
          const SizedBox(height: 10),
          _Headline(item: item),
        ],
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.item});
  final Map<String, Object?> item;

  @override
  Widget build(BuildContext context) {
    final title = '${item['title'] ?? ''}'.trim();
    final url = '${item['url'] ?? ''}'.trim();
    final source = '${item['source'] ?? ''}'.trim();
    final published = DateTime.tryParse('${item['published_at'] ?? ''}');
    final meta = [
      if (source.isNotEmpty) source,
      if (published != null) QaTime.ago(published),
    ].join(' · ');
    return QaTappable(
      onTap: url.isEmpty ? null : () => _open(url),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: QaText.bodyStrong.copyWith(fontSize: 13.5),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(meta, style: QaText.caption),
          ],
        ],
      ),
    );
  }

  static Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}

// ── h) Riesgo ─────────────────────────────────────────────────────────────

class _Risk extends StatelessWidget {
  const _Risk({required this.level, required this.beta});

  final String level;
  final double beta;

  static Widget? maybe(CompanyAnalysisData d) {
    final level = d.riskLevel;
    final beta = d.beta;
    if (level == null || beta == null) return null;
    return _Risk(level: level, beta: beta);
  }

  @override
  Widget build(BuildContext context) {
    final (String tag, String line) = switch (level) {
      ProfileCandidateMatcher.riskDefensive => (
        'Riesgo bajo',
        'Suele moverse menos que el mercado: en las caídas tiende a bajar menos.',
      ),
      ProfileCandidateMatcher.riskGrowth => (
        'Riesgo alto',
        'Suele moverse más que el mercado: sube y baja con más fuerza.',
      ),
      _ => (
        'Riesgo medio',
        'Suele moverse parecido al mercado en su conjunto.',
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QaSectionLabel(
          'Riesgo',
          trailing: QaTag(tag, icon: Icons.speed_rounded),
        ),
        const SizedBox(height: 6),
        Text('$line (beta ${_decimal(beta, 2)})', style: QaText.label),
      ],
    );
  }
}

// ── i) En tu cartera ──────────────────────────────────────────────────────

class _Holding extends StatelessWidget {
  const _Holding({required this.position});
  final Map<String, Object?> position;

  static Widget? maybe(CompanyAnalysisData d) {
    final p = d.position;
    if (p == null || p['weight_pct'] is! num) return null;
    return _Holding(position: p);
  }

  @override
  Widget build(BuildContext context) {
    final weight = (position['weight_pct'] as num).toDouble();
    final value = position['market_value'];
    final pnlAbs = position['pnl_abs'];
    final pnlPct = position['pnl_pct'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const QaSectionLabel('En tu cartera'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: QaStat(label: 'Peso', value: '${_decimal(weight, 1)}%'),
            ),
            if (value is num)
              Expanded(
                child: QaStat(label: 'Valor', value: QaFormat.money(value)),
              ),
            if (pnlAbs is num)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    QaStat(
                      label: 'Resultado',
                      value: QaFormat.signedMoney(pnlAbs),
                      valueColor: QaPalette.trend(pnlAbs),
                    ),
                    if (pnlPct is num) ...[
                      const SizedBox(height: 4),
                      PnlBadge(percent: pnlPct.toDouble(), compact: true),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ── j) Disclaimer ─────────────────────────────────────────────────────────

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 13,
          color: QaColors.textSecondary,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Análisis informativo, no asesoramiento financiero personalizado.',
            style: QaText.caption,
          ),
        ),
      ],
    );
  }
}
