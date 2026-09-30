import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_time.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_eps_history_chart.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_media_index.dart';
import 'package:portfolio_assistant/shared/utils/genui_helpers.dart';
import 'package:url_launcher/url_launcher.dart';

/// Widgets del catálogo sobre la compañía detrás de un ticker: calendario
/// de earnings, noticias y fundamentals.
abstract final class CompanyWidgets {
  // ---------------------------------------------------------------------
  // Earnings
  // ---------------------------------------------------------------------

  static Widget qaEarningsCalendar(CatalogItemContext ctx) {
    final data = _EarningsCalendarData.fromMap(ctx.data as JsonMap);
    final latest = data.latestResult;
    final hasAnything =
        data.hasNext || data.history.isNotEmpty || latest != null;

    return QaCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QaTickerHeader(
            ticker: data.ticker,
            trailing:
                data.fiscalPeriodLabel.isEmpty
                    ? null
                    : QaTag(data.fiscalPeriodLabel),
          ),
          if (data.hasNext) ...[
            const SizedBox(height: QaSpace.gap),
            _NextReportBlock(data: data),
          ],
          // Con un solo trimestre el "gráfico" no compara nada: la fila de
          // último reporte ya lo cuenta.
          if (data.history.length >= 2) ...[
            const SizedBox(height: QaSpace.sectionGap),
            const QaSectionLabel('Historial de EPS', trailing: QaEpsLegend()),
            const SizedBox(height: 10),
            QaEpsHistoryChart(quarters: data.history),
          ],
          if (latest != null) ...[
            const SizedBox(height: QaSpace.sectionGap),
            if (data.hasNext || data.history.length >= 2) ...[
              const QaDivider(),
              const SizedBox(height: QaSpace.gap),
            ],
            _LatestResultRow(result: latest),
          ],
          if (!hasAnything) ...[
            const SizedBox(height: QaSpace.gap),
            Text(
              'Sin fechas de reporte disponibles.',
              style: QaText.body.copyWith(color: QaColors.textSecondary),
            ),
          ],
          QaFollowUpBar(
            items: QaTickerFollowUps.of(
              data.ticker,
              exclude: {QaTickerFollowUps.earnings},
            ),
            limit: 3,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Noticias
  // ---------------------------------------------------------------------

  static Widget qaNewsSummary(CatalogItemContext ctx) {
    final data = _NewsSummaryData.fromMap(ctx.data as JsonMap);
    final tickers = data.tickers;
    final multi = tickers.length > 1;
    final media = NewsMediaIndex.instance;

    return QaCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (multi)
            QaCardTitle(
              title: 'Noticias',
              icon: Icons.article_outlined,
              subtitle: tickers.join(' · '),
            )
          else
            QaTickerHeader(
              ticker: data.ticker,
              trailing: const QaTag('Noticias', icon: Icons.article_outlined),
            ),
          if (data.items.isEmpty) ...[
            const SizedBox(height: QaSpace.gap),
            Text(
              'No hay noticias recientes.',
              style: QaText.body.copyWith(color: QaColors.textSecondary),
            ),
          ] else ...[
            const SizedBox(height: QaSpace.gap),
            _NewsHero(
              item: data.items.first,
              media: media.lookup(data.items.first.url),
              showTicker: multi,
            ),
            for (final item in data.items.skip(1)) ...[
              const QaDivider(),
              _NewsRow(
                item: item,
                media: media.lookup(item.url),
                showTicker: multi,
              ),
            ],
          ],
          if (data.ticker.isNotEmpty)
            QaFollowUpBar(
              items: QaTickerFollowUps.of(
                data.ticker,
                exclude: {QaTickerFollowUps.news},
              ),
              limit: 3,
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Fundamentals
  // ---------------------------------------------------------------------

  static Widget qaFundamentals(CatalogItemContext ctx) {
    final data = _FundamentalsData.fromMap(ctx.data as JsonMap);
    final marketCap = data.items.where((i) => i.isMarketCap).firstOrNull;
    final rest = data.items.where((i) => i != marketCap).toList();
    final sections =
        [
          for (final group in _FundamentalsGroup.values)
            (group, rest.where((i) => i.group == group).toList()),
        ].where((s) => s.$2.isNotEmpty).toList();
    final range = data.week52;

    return QaCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FundamentalsHeader(ticker: data.ticker, industry: data.industry),
          if (marketCap != null) ...[
            const SizedBox(height: QaSpace.gap),
            QaStat(
              label: 'Capitalización de mercado',
              value: marketCap.value,
              large: true,
            ),
          ],
          for (final (group, items) in sections) ...[
            const SizedBox(height: QaSpace.sectionGap),
            QaSectionLabel(group.label),
            const SizedBox(height: 10),
            _MetricGrid(items: items),
          ],
          if (range != null) ...[
            const SizedBox(height: QaSpace.sectionGap),
            _Week52Block(range: range),
          ],
          QaFollowUpBar(
            items: QaTickerFollowUps.of(
              data.ticker,
              exclude: {QaTickerFollowUps.fundamentals},
            ),
            limit: 3,
          ),
        ],
      ),
    );
  }
}

// =======================================================================
// Earnings — piezas
// =======================================================================

class _NextReportBlock extends StatelessWidget {
  const _NextReportBlock({required this.data});

  final _EarningsCalendarData data;

  @override
  Widget build(BuildContext context) {
    final date = data.nextReportDate;
    final countdown = date == null ? null : QaTime.countdown(date);
    final timing = data.timingLabel;
    final estimate = data.nextEpsEstimate;

    return QaInset(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('PRÓXIMO REPORTE', style: QaText.eyebrow),
                    const SizedBox(height: 6),
                    Text(
                      data.nextReportDateLabel,
                      style: QaText.displaySm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (estimate != null) ...[
                const SizedBox(width: QaSpace.gap),
                QaStat(
                  label: 'EPS estimado',
                  value: QaFormat.price(estimate),
                  crossAxisAlignment: CrossAxisAlignment.end,
                ),
              ],
            ],
          ),
          // Los tags van en su propia línea a todo el ancho: "Después del
          // cierre" no entra al lado del EPS en pantallas chicas.
          if (countdown != null || timing.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (countdown != null)
                  QaTag(
                    countdown,
                    color: QaColors.accentBlue,
                    icon: Icons.schedule_rounded,
                  ),
                if (timing.isNotEmpty) QaTag(timing, icon: _timingIcon(timing)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static IconData _timingIcon(String label) {
    final l = label.toLowerCase();
    if (l.contains('antes')) return Icons.wb_sunny_outlined;
    if (l.contains('después') || l.contains('cierre')) {
      return Icons.nightlight_outlined;
    }
    return Icons.access_time_rounded;
  }
}

class _LatestResultRow extends StatelessWidget {
  const _LatestResultRow({required this.result});

  final _LatestResult result;

  @override
  Widget build(BuildContext context) {
    final beat = result.beat;
    final surprise = result.surprisePct;
    final when = result.dateLabel;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                when.isEmpty ? 'Último reporte' : 'Último reporte · $when',
                style: QaText.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'EPS ${QaFormat.price(result.actual)}',
                      style: QaText.value,
                    ),
                    TextSpan(
                      text: '  vs. ${QaFormat.price(result.estimate)} est.',
                      style: QaText.label,
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            QaTag(
              beat ? 'Superó' : 'No alcanzó',
              color: beat ? QaColors.profit : QaColors.loss,
              icon: beat ? Icons.check_rounded : Icons.close_rounded,
            ),
            if (surprise != null && surprise != 0) ...[
              const SizedBox(height: 4),
              QaDeltaChip(value: surprise, digits: 1, dense: true),
            ],
          ],
        ),
      ],
    );
  }
}

// =======================================================================
// Noticias — piezas
// =======================================================================

/// Abre el artículo en el navegador del sistema. Nunca lanza: un link roto
/// no puede tumbar la card.
Future<void> _openArticle(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

String _newsMeta(_NewsItem item, NewsMedia? media, {required bool showTicker}) {
  // Si el modelo ya escribió una fecha relativa, se respeta; si escribió
  // una absoluta (o nada) y conocemos el timestamp real, se calcula acá con
  // más precisión ("hace 2 h").
  final date =
      media != null &&
              (item.dateLabel.isEmpty || !QaTime.looksRelative(item.dateLabel))
          ? QaTime.ago(media.publishedAt)
          : item.dateLabel;
  return [
    if (showTicker && item.ticker.isNotEmpty) item.ticker,
    if (item.source.isNotEmpty) item.source,
    if (date.isNotEmpty) date,
  ].join(' · ');
}

VoidCallback? _tapFor(_NewsItem item) =>
    item.url.isEmpty ? null : () => _openArticle(item.url);

/// Imagen de red que, si falla, desaparece (sin caja rota). Mientras carga
/// reserva el lugar con el tono de inset para no saltar al llegar.
class _NewsImage extends StatelessWidget {
  const _NewsImage({
    required this.url,
    required this.radius,
    this.aspectRatio,
    this.size,
    this.bottomGap = 0,
  });

  final String url;
  final double radius;
  final double? aspectRatio;
  final double? size;
  final double bottomGap;

  @override
  Widget build(BuildContext context) {
    Widget frame(Widget child) {
      final boxed =
          size != null
              ? SizedBox.square(dimension: size, child: child)
              : AspectRatio(aspectRatio: aspectRatio ?? 16 / 9, child: child);
      return Padding(
        padding: EdgeInsets.only(bottom: bottomGap),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: boxed,
        ),
      );
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      width: size,
      height: size,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
      frameBuilder: (context, child, frameIndex, sync) {
        if (frameIndex == null && !sync) {
          return frame(ColoredBox(color: QaPalette.inset));
        }
        return frame(child);
      },
    );
  }
}

class _NewsHero extends StatelessWidget {
  const _NewsHero({
    required this.item,
    required this.media,
    required this.showTicker,
  });

  final _NewsItem item;
  final NewsMedia? media;
  final bool showTicker;

  @override
  Widget build(BuildContext context) {
    final image = media?.imageUrl;
    final meta = _newsMeta(item, media, showTicker: showTicker);
    return QaTappable(
      onTap: _tapFor(item),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (image != null)
              _NewsImage(
                url: image,
                radius: QaSpace.insetRadius,
                aspectRatio: 16 / 9,
                bottomGap: 12,
              ),
            Text(
              item.headline,
              style: QaText.bodyStrong.copyWith(fontSize: 15),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (item.summaryLine.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                item.summaryLine,
                style: QaText.body.copyWith(
                  color: QaColors.textSecondary,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 8),
              _MetaLine(
                meta: meta,
                linked: item.url.isNotEmpty,
                sourceDomain: media?.sourceDomain,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NewsRow extends StatelessWidget {
  const _NewsRow({
    required this.item,
    required this.media,
    required this.showTicker,
  });

  final _NewsItem item;
  final NewsMedia? media;
  final bool showTicker;

  @override
  Widget build(BuildContext context) {
    final image = media?.imageUrl;
    final meta = _newsMeta(item, media, showTicker: showTicker);
    return QaTappable(
      onTap: _tapFor(item),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.headline,
                      style: QaText.bodyStrong,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _MetaLine(
                        meta: meta,
                        linked: item.url.isNotEmpty,
                        sourceDomain: media?.sourceDomain,
                      ),
                    ],
                  ],
                ),
              ),
              if (image != null) ...[
                const SizedBox(width: QaSpace.gap),
                _NewsImage(url: image, radius: QaSpace.chipRadius, size: 56),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.meta,
    required this.linked,
    this.sourceDomain,
  });

  final String meta;
  final bool linked;

  /// Con dominio, el logo del medio antecede a la línea: la señal de
  /// confianza más rápida de leer ("esto es de Reuters").
  final String? sourceDomain;

  @override
  Widget build(BuildContext context) {
    final domain = sourceDomain;
    return Row(
      children: [
        if (domain != null) ...[
          _SourceLogo(domain: domain),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            meta,
            style: QaText.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (linked) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.north_east_rounded,
            size: 11,
            color: QaColors.textSecondary,
          ),
        ],
      ],
    );
  }
}

// =======================================================================
// Fundamentals — piezas
// =======================================================================

enum _FundamentalsGroup {
  valuation('valuation', 'Valuación'),
  profitability('profitability', 'Rentabilidad'),
  dividend('dividend', 'Dividendo'),
  other('other', 'Otros');

  const _FundamentalsGroup(this.key, this.label);

  final String key;
  final String label;

  static _FundamentalsGroup? fromKey(Object? key) {
    for (final g in values) {
      if (g.key == key) return g;
    }
    return null;
  }

  /// Fallback cuando el modelo no manda `group` (payloads viejos): se
  /// infiere del rótulo, que el modelo escribe en español o inglés.
  static _FundamentalsGroup infer(String label) {
    final l = label.toLowerCase();
    bool any(List<String> keys) => keys.any(l.contains);
    if (any(['dividend', 'payout', 'reparto'])) return dividend;
    if (any([
      'margen',
      'margin',
      'roe',
      'roa',
      'rentab',
      'eps',
      'crecim',
      'growth',
      'ganancia',
    ])) {
      return profitability;
    }
    if (any([
      'p/',
      'pe ',
      'per ',
      'ev/',
      'peg',
      'market cap',
      'capitaliz',
      'valuaci',
      'precio/',
    ])) {
      return valuation;
    }
    return other;
  }
}

class _FundamentalsHeader extends StatelessWidget {
  const _FundamentalsHeader({required this.ticker, required this.industry});

  final String ticker;
  final String industry;

  @override
  Widget build(BuildContext context) {
    if (industry.isEmpty) return QaTickerHeader(ticker: ticker);
    // Nombre de la compañía (cliente) + industria (modelo) en el subtítulo.
    return QaBrandBuilder(
      ticker: ticker,
      builder: (context, brand) {
        final name = brand.name;
        return QaTickerHeader(
          ticker: ticker,
          subtitle:
              name == null || name.isEmpty ? industry : '$name · $industry',
        );
      },
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.items});

  final List<_FundamentalsMetricItem> items;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (var i = 0; i < items.length; i += 2)
        items.sublist(i, i + 2 > items.length ? items.length : i + 2),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _MetricCell(item: rows[r][0])),
              const SizedBox(width: QaSpace.gap),
              Expanded(
                child:
                    rows[r].length > 1
                        ? _MetricCell(item: rows[r][1])
                        : const SizedBox(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.item});

  final _FundamentalsMetricItem item;

  @override
  Widget build(BuildContext context) {
    final bar = item.barFraction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.label,
          style: QaText.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          item.value,
          style: QaText.value.copyWith(
            color: (item.percent ?? 0) < 0 ? QaColors.loss : null,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (bar != null) ...[
          const SizedBox(height: 6),
          QaProgressBar(
            value: bar,
            height: 4,
            color: item.percent! < 0 ? QaColors.loss : QaColors.accentBlue,
          ),
        ],
      ],
    );
  }
}

class _Week52Block extends StatelessWidget {
  const _Week52Block({required this.range});

  final _Week52Range range;

  @override
  Widget build(BuildContext context) {
    final price = range.current;
    final fromHigh = price == null ? null : (price / range.high - 1) * 100;
    return QaInset(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          QaSectionLabel(
            'Rango 52 semanas',
            trailing:
                price == null
                    ? null
                    : Text(QaFormat.price(price), style: QaText.valueSm),
          ),
          const SizedBox(height: 10),
          if (price != null)
            QaRangeBar(
              min: range.low,
              max: range.high,
              value: price,
              minLabel: QaFormat.price(range.low),
              maxLabel: QaFormat.price(range.high),
            )
          else
            Row(
              children: [
                Expanded(
                  child: QaStat(
                    label: 'Mínimo',
                    value: QaFormat.price(range.low),
                  ),
                ),
                Expanded(
                  child: QaStat(
                    label: 'Máximo',
                    value: QaFormat.price(range.high),
                    crossAxisAlignment: CrossAxisAlignment.end,
                  ),
                ),
              ],
            ),
          if (fromHigh != null && fromHigh < -0.05) ...[
            const SizedBox(height: 8),
            Text(
              'A ${QaFormat.pct(fromHigh.abs())} del máximo',
              style: QaText.caption,
            ),
          ],
        ],
      ),
    );
  }
}

// =======================================================================
// Modelos de datos
// =======================================================================

double? _optDouble(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.replaceAll(',', '.'));
  return null;
}

final class _LatestResult {
  const _LatestResult({
    required this.actual,
    required this.estimate,
    required this.beat,
    required this.dateLabel,
  });

  final double actual;
  final double estimate;
  final bool beat;
  final String dateLabel;

  double? get surprisePct =>
      estimate == 0 ? null : (actual - estimate) / estimate.abs() * 100;
}

final class _EarningsCalendarData {
  _EarningsCalendarData({
    required this.ticker,
    required this.nextReportDateLabel,
    required this.nextReportDate,
    required this.fiscalPeriodLabel,
    required this.timingLabel,
    required this.nextEpsEstimate,
    required this.latestResult,
    required this.history,
  });

  factory _EarningsCalendarData.fromMap(JsonMap map) {
    String str(String key) =>
        GenUiHelpers.safeString(map[key], defaultValue: '').trim();

    final history = <QaEpsQuarter>[];
    final rawHistory = map['history'];
    if (rawHistory is List) {
      for (final raw in rawHistory.whereType<Map>()) {
        final actual = _optDouble(raw['epsActual']);
        final estimate = _optDouble(raw['epsEstimate']);
        if (actual == null || estimate == null) continue;
        history.add(
          QaEpsQuarter(
            label: GenUiHelpers.safeString(
              raw['periodLabel'],
              defaultValue: '',
            ),
            actual: actual,
            estimate: estimate,
          ),
        );
      }
    }
    // Máximo 4, los más recientes (el schema pide del más viejo al nuevo).
    final quarters =
        history.length > 4 ? history.sublist(history.length - 4) : history;

    final actual = _optDouble(map['epsActual']);
    final estimate = _optDouble(map['epsEstimate']);
    _LatestResult? latest;
    if (actual != null && estimate != null) {
      final beatRaw = map['beat'];
      latest = _LatestResult(
        actual: actual,
        estimate: estimate,
        beat:
            beatRaw == null
                ? actual >= estimate
                : GenUiHelpers.safeBool(
                  beatRaw,
                  defaultValue: actual >= estimate,
                ),
        dateLabel: str('latestReportDateLabel'),
      );
    } else if (quarters.isNotEmpty) {
      // El modelo mandó historial pero no el último resultado: el trimestre
      // más nuevo del historial ES el último reporte.
      final last = quarters.last;
      latest = _LatestResult(
        actual: last.actual,
        estimate: last.estimate,
        beat: last.beat,
        dateLabel: last.label,
      );
    }

    final iso = str('nextReportDate');
    return _EarningsCalendarData(
      ticker: str('ticker').toUpperCase(),
      nextReportDateLabel: str('nextReportDateLabel'),
      nextReportDate: iso.isEmpty ? null : DateTime.tryParse(iso),
      fiscalPeriodLabel: str('fiscalPeriodLabel'),
      timingLabel: str('timingLabel'),
      nextEpsEstimate: _optDouble(map['nextEpsEstimate']),
      latestResult: latest,
      history: quarters,
    );
  }

  final String ticker;
  final String nextReportDateLabel;
  final DateTime? nextReportDate;
  final String fiscalPeriodLabel;
  final String timingLabel;
  final double? nextEpsEstimate;
  final _LatestResult? latestResult;
  final List<QaEpsQuarter> history;

  bool get hasNext => nextReportDateLabel.isNotEmpty;
}

final class _NewsItem {
  _NewsItem({
    required this.headline,
    required this.summaryLine,
    required this.dateLabel,
    required this.source,
    required this.url,
    required this.ticker,
  });

  factory _NewsItem.fromMap(Map map) {
    String str(String key) =>
        GenUiHelpers.safeString(map[key], defaultValue: '').trim();
    return _NewsItem(
      headline: str('headline'),
      summaryLine: str('summaryLine'),
      dateLabel: str('dateLabel'),
      source: str('source'),
      url: str('url'),
      ticker: str('ticker').toUpperCase(),
    );
  }

  final String headline;
  final String summaryLine;
  final String dateLabel;
  final String source;
  final String url;
  final String ticker;
}

final class _NewsSummaryData {
  _NewsSummaryData({required this.ticker, required this.items});

  factory _NewsSummaryData.fromMap(JsonMap map) {
    final raw = map['items'];
    final items =
        [
          if (raw is List)
            for (final item in raw.whereType<Map>()) _NewsItem.fromMap(item),
        ].where((i) => i.headline.isNotEmpty).take(3).toList();
    return _NewsSummaryData(
      ticker:
          GenUiHelpers.safeString(
            map['ticker'],
            defaultValue: '',
          ).trim().toUpperCase(),
      items: items,
    );
  }

  final String ticker;
  final List<_NewsItem> items;

  /// Tickers distintos presentes en la card (el de la card primero).
  List<String> get tickers {
    final set = <String>{
      if (ticker.isNotEmpty) ticker,
      for (final i in items)
        if (i.ticker.isNotEmpty) i.ticker,
    };
    return set.toList();
  }
}

final class _FundamentalsMetricItem {
  _FundamentalsMetricItem({
    required this.label,
    required this.value,
    required this.group,
  });

  factory _FundamentalsMetricItem.fromMap(Map map) {
    final label = GenUiHelpers.safeString(map['label'], defaultValue: '');
    return _FundamentalsMetricItem(
      label: label,
      value: GenUiHelpers.safeString(map['value'], defaultValue: ''),
      group:
          _FundamentalsGroup.fromKey(map['group']) ??
          _FundamentalsGroup.infer(label),
    );
  }

  final String label;
  final String value;
  final _FundamentalsGroup group;

  static final _pctPattern = RegExp(r'(-?\d+(?:[.,]\d+)?)\s*%');

  bool get isMarketCap {
    final l = label.toLowerCase();
    return l.contains('market cap') || l.contains('capitaliz');
  }

  /// El valor como porcentaje, si el texto es un porcentaje ("67,94%").
  double? get percent {
    final match = _pctPattern.firstMatch(value);
    if (match == null) return null;
    return double.tryParse(match.group(1)!.replaceAll(',', '.'));
  }

  /// Fracción 0..1 para la barra, solo en métricas donde "cuánto del
  /// total" tiene sentido (márgenes, ROE, payout). Un dividend yield de
  /// 0,5% como barra sería ruido.
  double? get barFraction {
    final p = percent;
    if (p == null) return null;
    final isPayout = label.toLowerCase().contains('payout');
    if (group != _FundamentalsGroup.profitability && !isPayout) return null;
    return (p.abs() / 100).clamp(0.0, 1.0);
  }
}

final class _Week52Range {
  const _Week52Range({required this.low, required this.high, this.current});

  final double low;
  final double high;
  final double? current;
}

final class _FundamentalsData {
  _FundamentalsData({
    required this.ticker,
    required this.industry,
    required this.items,
    required this.week52,
  });

  factory _FundamentalsData.fromMap(JsonMap map) {
    final raw = map['items'];
    final items =
        [
              if (raw is List)
                for (final item in raw.whereType<Map>())
                  _FundamentalsMetricItem.fromMap(item),
            ]
            .where((i) => i.label.isNotEmpty && i.value.isNotEmpty)
            .take(8)
            .toList();

    final low = _optDouble(map['week52Low']);
    final high = _optDouble(map['week52High']);
    final current = _optDouble(map['currentPrice']);
    return _FundamentalsData(
      ticker:
          GenUiHelpers.safeString(
            map['ticker'],
            defaultValue: '',
          ).trim().toUpperCase(),
      industry:
          GenUiHelpers.safeString(map['industry'], defaultValue: '').trim(),
      items: items,
      week52:
          low != null && high != null && low > 0 && high > low
              ? _Week52Range(
                low: low,
                high: high,
                current: current != null && current > 0 ? current : null,
              )
              : null,
    );
  }

  final String ticker;
  final String industry;
  final List<_FundamentalsMetricItem> items;
  final _Week52Range? week52;
}

/// Favicon del medio vía el servicio público de Google (el mismo origen
/// que las notas). Si falla, no ocupa lugar.
class _SourceLogo extends StatelessWidget {
  const _SourceLogo({required this.domain});

  final String domain;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Image.network(
        'https://www.google.com/s2/favicons?domain=$domain&sz=64',
        width: 14,
        height: 14,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}
