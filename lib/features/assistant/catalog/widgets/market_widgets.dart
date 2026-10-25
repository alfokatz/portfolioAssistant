import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_compare_chart.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_market_parts.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_price_chart.dart';
import 'package:portfolio_assistant/features/assistant/services/price_chart_data_loader.dart';
import 'package:portfolio_assistant/shared/utils/genui_helpers.dart';

/// Widgets del catálogo sobre el precio de un ticker y comparaciones entre
/// tickers: gráfico de precio, gráfico comparado, snapshot, movimiento y
/// comparativas.
abstract final class MarketWidgets {
  static Widget qaTickerSnapshot(CatalogItemContext ctx) {
    return QaCardShell(
      child: _tickerSnapshotContent(
        _TickerSnapshotData.fromMap(ctx.data as JsonMap),
      ),
    );
  }

  /// Contenido de `QaTickerSnapshot` sin la card — lo reusa `QaPriceChart`
  /// como fallback dentro de su propia card.
  static Widget _tickerSnapshotContent(_TickerSnapshotData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        QaTickerHeader(
          ticker: data.ticker,
          trailing: QaMarketParts.weightTag(data.weightPct),
        ),
        const SizedBox(height: QaSpace.sectionGap),
        Text(
          data.currentPrice > 0 ? QaFormat.price(data.currentPrice) : '—',
          style: QaText.display,
        ),
        const SizedBox(height: 4),
        Text('Precio actual', style: QaText.label),
        // Del número protagonista al detalle: salto de sección, sin línea.
        if (data.periods.isNotEmpty) ...[
          const SizedBox(height: QaSpace.sectionGap),
          _PeriodChips(periods: data.periods),
        ],
        // Sin histórico, "Gráfico" volvería a esta misma card.
        QaFollowUpBar(
          items: QaTickerFollowUps.of(
            data.ticker,
            exclude: {QaTickerFollowUps.chart},
          ),
          limit: 3,
        ),
      ],
    );
  }

  static Widget qaTickerMove(CatalogItemContext ctx) {
    return QaCardShell(
      child: _tickerMoveContent(_TickerMoveData.fromMap(ctx.data as JsonMap)),
    );
  }

  /// Contenido de `QaTickerMove` sin la card (ver [_tickerSnapshotContent]).
  /// [periods] solo llega desde el fallback de `QaPriceChart`, cuyo payload
  /// trae además día/semana/mes.
  static Widget _tickerMoveContent(
    _TickerMoveData data, {
    List<(String, double)> periods = const [],
  }) {
    final hasPrices = data.priceStart > 0 && data.priceEnd > 0;
    final periodLabel = QaMarketParts.capitalize(data.periodLabel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        QaTickerHeader(
          ticker: data.ticker,
          trailing: QaMarketParts.weightTag(data.weightPct),
        ),
        const SizedBox(height: QaSpace.sectionGap),
        if (data.priceEnd > 0)
          Text(QaFormat.price(data.priceEnd), style: QaText.display)
        else
          Text(
            QaFormat.signedPct(data.changePct),
            style: QaText.display.copyWith(
              color: QaPalette.trend(data.changePct),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            QaDeltaChip(
              value: data.changePct,
              text:
                  hasPrices
                      ? '${QaFormat.price((data.priceEnd - data.priceStart).abs())} '
                          '(${QaFormat.pct(data.changePct.abs(), digits: 2)})'
                      : null,
            ),
            if (periodLabel.isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  periodLabel,
                  style: QaText.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        // Del número protagonista al detalle: salto de sección, sin línea;
        // entre los bloques de detalle, el aire chico de un mismo grupo.
        if (hasPrices) ...[
          const SizedBox(height: QaSpace.sectionGap),
          QaInset(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: QaStatGrid(
              columns: 3,
              stats: [
                QaStat(label: 'Inicio', value: QaFormat.price(data.priceStart)),
                QaStat(label: 'Cierre', value: QaFormat.price(data.priceEnd)),
                QaStat(
                  label: 'Diferencia',
                  value: QaFormat.signedPrice(data.priceEnd - data.priceStart),
                  valueColor: QaPalette.trend(data.priceEnd - data.priceStart),
                ),
              ],
            ),
          ),
        ],
        if (periods.isNotEmpty) ...[
          SizedBox(height: hasPrices ? QaSpace.gap : QaSpace.sectionGap),
          _PeriodChips(periods: periods),
        ],
        QaFollowUpBar(
          items: QaTickerFollowUps.of(
            data.ticker,
            exclude: {QaTickerFollowUps.chart},
          ),
          limit: 3,
        ),
      ],
    );
  }

  /// Gráfico de precio histórico. Si el período inicial no tiene datos, la
  /// misma card muestra el contenido de `QaTickerMove` (si el modelo mandó
  /// los campos de un período explícito) o de `QaTickerSnapshot` — ver
  /// `QaPriceChart`.
  static Widget qaPriceChart(CatalogItemContext ctx) {
    final map = ctx.data as JsonMap;
    final data = _PriceChartData.fromMap(map);
    final fallback =
        data.hasExplicitPeriod
            ? _tickerMoveContent(
              _TickerMoveData.fromMap(map),
              periods: _TickerSnapshotData.fromMap(map).periods,
            )
            : _tickerSnapshotContent(_TickerSnapshotData.fromMap(map));

    return QaCardShell.staged(
      staged:
          (context, active, onFinished) => QaPriceChart(
            ticker: data.ticker,
            initialRange: data.initialRange,
            weightPct: data.weightPct,
            fallback: fallback,
            active: active,
            onFinished: onFinished,
          ),
    );
  }

  /// Rendimiento comparado de 2–3 tickers. Sin histórico para ninguno, la
  /// card muestra los % que mandó el modelo (`items`) con el mismo diseño
  /// de `QaMetricStrip`.
  static Widget qaCompareChart(CatalogItemContext ctx) {
    final data = _CompareChartData.fromMap(ctx.data as JsonMap);
    final fallback = _compareFallback(data);
    if (data.tickers.isEmpty) return QaCardShell(child: fallback);

    return QaCardShell.staged(
      staged:
          (context, active, onFinished) => QaCompareChart(
            tickers: data.tickers,
            initialRange: data.initialRange,
            fallback: fallback,
            active: active,
            onFinished: onFinished,
          ),
    );
  }

  static Widget _compareFallback(_CompareChartData data) {
    final range = QaCompareChart.supportedRange(data.initialRange);
    final subtitle = 'Variación · ${QaMarketParts.rangeSummaryLabel(range)}';
    if (data.items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          CompareHeader(tickers: data.tickers, subtitle: subtitle),
          const SizedBox(height: QaSpace.gap),
          Text(
            'No hay histórico de precios para comparar en este momento.',
            style: QaText.label,
          ),
        ],
      );
    }
    return _TickerComparisonList(
      items: [
        for (final item in data.items)
          _MetricItem(
            label: item.ticker,
            value: QaFormat.signedPct(item.changePct),
            trend:
                item.changePct > 0
                    ? 'up'
                    : (item.changePct < 0 ? 'down' : 'neutral'),
          ),
      ],
      subtitle: subtitle,
    );
  }

  static Widget qaMetricStrip(CatalogItemContext ctx) {
    final data = _MetricStripData.fromMap(ctx.data as JsonMap);
    final periodLabel = QaMarketParts.capitalize(data.periodLabel);
    if (data.items.isEmpty) {
      return QaCardShell(
        child: Text('Sin datos para comparar.', style: QaText.label),
      );
    }
    return QaCardShell(
      child:
          data.items.every((i) => QaMarketParts.looksLikeTicker(i.label))
              ? _TickerComparisonList(
                items: data.items,
                subtitle:
                    periodLabel.isEmpty
                        ? 'Variación de precio'
                        : 'Variación · $periodLabel',
              )
              : _MetricColumns(items: data.items),
    );
  }

  static Widget qaComparisonRow(CatalogItemContext ctx) {
    final data = _ComparisonRowData.fromMap(ctx.data as JsonMap);
    final left = QaMarketParts.parseLooseNumber(data.leftValue);
    final right = QaMarketParts.parseLooseNumber(data.rightValue);
    final signed =
        QaMarketParts.isSignedValue(data.leftValue) ||
        QaMarketParts.isSignedValue(data.rightValue);
    final winner =
        left == null || right == null || left == right
            ? null
            : (left > right ? 0 : 1);
    final maxAbs = math.max(left?.abs() ?? 0, right?.abs() ?? 0);
    double share(double? v) => v == null || maxAbs == 0 ? 0 : v.abs() / maxAbs;

    Widget side(int index, String ticker, String value, double? number) =>
        Expanded(
          child: _ComparisonSide(
            ticker: ticker,
            value: value,
            number: number,
            signed: signed,
            share: share(number),
            isWinner: winner == index,
            winnerLabel: signed ? 'Mejor' : 'Mayor',
          ),
        );

    final tickers = [
      if (data.leftTicker.isNotEmpty) data.leftTicker,
      if (data.rightTicker.isNotEmpty) data.rightTicker,
    ];

    return QaCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          QaCardTitle(
            title: data.label.isEmpty ? 'Comparación' : data.label,
            icon: Icons.compare_arrows_rounded,
            subtitle: data.metricLabel,
          ),
          const SizedBox(height: QaSpace.sectionGap),
          Row(
            children: [
              side(0, data.leftTicker, data.leftValue, left),
              const _VsBadge(),
              side(1, data.rightTicker, data.rightValue, right),
            ],
          ),
          if (tickers.length == 2)
            QaFollowUpBar(
              items: [
                QaFollowUp(
                  'Gráfico comparado',
                  'Compará el rendimiento de ${tickers[0]} y ${tickers[1]} '
                      'en el último año',
                  icon: Icons.stacked_line_chart_rounded,
                ),
                for (final t in tickers)
                  QaFollowUp(
                    'Noticias de $t',
                    '¿Qué noticias hay de $t?',
                    icon: Icons.article_outlined,
                    feature: PlanFeature.news,
                    ticker: t,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Día / Semana / Mes como chips de variación en un bloque teñido.
class _PeriodChips extends StatelessWidget {
  const _PeriodChips({required this.periods});

  final List<(String, double)> periods;

  @override
  Widget build(BuildContext context) {
    return QaInset(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          for (final (label, value) in periods)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: QaText.label),
                  const SizedBox(height: 6),
                  QaDeltaChip(value: value),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Comparación de 2–3 tickers en filas de ancho completo: identidad
/// (avatar + nombre), variación y una barra de magnitud relativa. El que
/// lidera queda sobre un bloque teñido con un tag — énfasis sutil, el
/// texto de Porty es el que concluye.
class _TickerComparisonList extends StatelessWidget {
  const _TickerComparisonList({required this.items, required this.subtitle});

  final List<_MetricItem> items;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final numbers = [
      for (final i in items) QaMarketParts.parseLooseNumber(i.value),
    ];
    // El signo lo decide `trend` (el modelo puede mandar "1,2%" sin "+").
    final signedNumbers = [
      for (var k = 0; k < items.length; k++)
        numbers[k] == null
            ? null
            : numbers[k]!.abs() * (items[k].trend == 'down' ? -1 : 1),
    ];
    final valid = signedNumbers.whereType<double>().toList();
    final maxAbs =
        valid.isEmpty ? 0.0 : valid.map((v) => v.abs()).reduce(math.max);
    int? leader;
    if (valid.length >= 2 && valid.toSet().length > 1) {
      final best = valid.reduce(math.max);
      leader = signedNumbers.indexOf(best);
    }
    final tickers = [for (final i in items) i.label];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CompareHeader(tickers: tickers, subtitle: subtitle),
        // Cada fila trae su propio padding (para el bloque teñido del que
        // lidera): se descuenta para que el aire visible sea el del kit —
        // salto de sección bajo el encabezado, solo espacio entre filas.
        const SizedBox(
          height: QaSpace.sectionGap - _TickerCompareRow.verticalPadding,
        ),
        for (var k = 0; k < items.length; k++) ...[
          if (k > 0)
            const SizedBox(
              height: QaSpace.rowGap - 2 * _TickerCompareRow.verticalPadding,
            ),
          QaTappable(
            question: '¿Cómo viene ${items[k].label}?',
            child: _TickerCompareRow(
              item: items[k],
              share:
                  signedNumbers[k] == null || maxAbs == 0
                      ? 0
                      : signedNumbers[k]!.abs() / maxAbs,
              isLeader: leader == k,
            ),
          ),
        ],
        if (tickers.length >= 2)
          QaFollowUpBar(
            items: [
              QaFollowUp(
                'Gráfico 1 año',
                'Compará el rendimiento de ${tickers.take(3).join(' y ')} '
                    'en el último año',
                icon: Icons.stacked_line_chart_rounded,
              ),
              ...compareFollowUps(tickers).take(2),
            ],
          ),
      ],
    );
  }
}

class _TickerCompareRow extends StatelessWidget {
  const _TickerCompareRow({
    required this.item,
    required this.share,
    required this.isLeader,
  });

  final _MetricItem item;
  final double share;
  final bool isLeader;

  /// Padding vertical de la fila; la lista lo descuenta de sus gaps.
  static const verticalPadding = 6.0;

  @override
  Widget build(BuildContext context) {
    final direction = switch (item.trend) {
      'up' => 1,
      'down' => -1,
      _ => 0,
    };
    final magnitude = item.value.replaceAll(RegExp(r'^\s*[+\-−]'), '');
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.fromLTRB(
        10,
        verticalPadding,
        12,
        verticalPadding,
      ),
      decoration: BoxDecoration(
        color: isLeader ? QaPalette.inset : Colors.transparent,
        borderRadius: BorderRadius.circular(QaSpace.insetRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          QaBrandBuilder(
            ticker: item.label,
            builder:
                (context, brand) => Row(
                  children: [
                    QaTickerAvatar(ticker: item.label, brand: brand, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item.label,
                                  style: QaText.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isLeader) ...[
                                const SizedBox(width: 6),
                                QaTag('Lidera', color: QaColors.accentBlue),
                              ],
                            ],
                          ),
                          if (brand.name case final name? when name.isNotEmpty)
                            Text(
                              name,
                              style: QaText.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    QaDeltaChip(value: direction, text: magnitude),
                  ],
                ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 42),
            child: QaProgressBar(
              value: share,
              height: 4,
              color:
                  direction == 0
                      ? QaColors.textSecondary
                      : QaPalette.trend(direction),
            ),
          ),
        ],
      ),
    );
  }
}

/// Métricas que no son tickers ("Valor", "P&L"): columnas con el valor
/// grande y la flecha de tendencia.
class _MetricColumns extends StatelessWidget {
  const _MetricColumns({required this.items});

  final List<_MetricItem> items;

  @override
  Widget build(BuildContext context) {
    return QaStatGrid(
      columns: items.length,
      stats: [
        for (final item in items)
          QaStat(
            label: item.label,
            value: item.value,
            large: true,
            valueColor: switch (item.trend) {
              'up' => QaColors.profit,
              'down' => QaColors.loss,
              _ => null,
            },
            trailing:
                item.trend == 'neutral'
                    ? null
                    : Icon(
                      item.trend == 'up'
                          ? Icons.arrow_drop_up_rounded
                          : Icons.arrow_drop_down_rounded,
                      size: 20,
                      color: QaPalette.trend(item.trend == 'up' ? 1 : -1),
                    ),
          ),
      ],
    );
  }
}

/// Una mitad de `QaComparisonRow`: identidad, valor grande y barra de
/// magnitud relativa a la otra mitad.
class _ComparisonSide extends StatelessWidget {
  const _ComparisonSide({
    required this.ticker,
    required this.value,
    required this.number,
    required this.signed,
    required this.share,
    required this.isWinner,
    required this.winnerLabel,
  });

  final String ticker;
  final String value;
  final double? number;
  final bool signed;
  final double share;
  final bool isWinner;
  final String winnerLabel;

  @override
  Widget build(BuildContext context) {
    final n = number;
    final color = signed && n != null && n != 0 ? QaPalette.trend(n) : null;
    return QaTappable(
      question: ticker.isEmpty ? null : '¿Cómo viene $ticker?',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isWinner ? QaPalette.inset : Colors.transparent,
          borderRadius: BorderRadius.circular(QaSpace.insetRadius),
          border: Border.all(
            color: isWinner ? Colors.transparent : QaColors.border,
          ),
        ),
        child: QaBrandBuilder(
          ticker: ticker,
          builder:
              (context, brand) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      QaTickerAvatar(ticker: ticker, brand: brand, size: 28),
                      const Spacer(),
                      if (isWinner)
                        QaTag(winnerLabel, color: QaColors.accentBlue),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    ticker.isEmpty ? '—' : ticker,
                    style: QaText.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    brand.name ?? '',
                    style: QaText.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    value.isEmpty ? '—' : value,
                    style: QaText.displaySm.copyWith(color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  QaProgressBar(
                    value: share,
                    height: 4,
                    color: color ?? QaColors.textPrimary,
                  ),
                ],
              ),
        ),
      ),
    );
  }
}

class _VsBadge extends StatelessWidget {
  const _VsBadge();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      child: Center(
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: QaColors.surfaceCard,
            shape: BoxShape.circle,
            border: Border.all(color: QaColors.border),
          ),
          child: Text('vs', style: QaText.caption),
        ),
      ),
    );
  }
}

double? _optionalDouble(Object? value) =>
    value == null ? null : GenUiHelpers.safeDouble(value, defaultValue: 0);

final class _TickerSnapshotData {
  _TickerSnapshotData({
    required this.ticker,
    required this.currentPrice,
    required this.periods,
    required this.weightPct,
  });

  factory _TickerSnapshotData.fromMap(JsonMap map) {
    final day = _optionalDouble(map['dayChangePct']);
    final week = _optionalDouble(map['weekChangePct']);
    final month = _optionalDouble(map['monthChangePct']);
    return _TickerSnapshotData(
      ticker: GenUiHelpers.safeString(map['ticker'], defaultValue: ''),
      currentPrice: GenUiHelpers.safeDouble(
        map['currentPrice'],
        defaultValue: 0,
      ),
      periods: [
        if (day != null) ('Día', day),
        if (week != null) ('Semana', week),
        if (month != null) ('Mes', month),
      ],
      weightPct: GenUiHelpers.safeDouble(map['weightPct'], defaultValue: 0),
    );
  }

  final String ticker;
  final double currentPrice;

  /// Solo los períodos que vinieron en el payload.
  final List<(String, double)> periods;
  final double weightPct;
}

final class _PriceChartData {
  _PriceChartData({
    required this.ticker,
    required this.initialRange,
    required this.weightPct,
    required this.hasExplicitPeriod,
  });

  factory _PriceChartData.fromMap(JsonMap map) {
    return _PriceChartData(
      ticker: GenUiHelpers.safeString(map['ticker'], defaultValue: ''),
      initialRange: PriceChartRange.fromWire(
        GenUiHelpers.safeString(map['initialRange'], defaultValue: ''),
      ),
      weightPct: GenUiHelpers.safeDouble(map['weightPct'], defaultValue: 0),
      hasExplicitPeriod:
          GenUiHelpers.safeString(
            map['periodLabel'],
            defaultValue: '',
          ).isNotEmpty &&
          map['changePct'] != null,
    );
  }

  final String ticker;
  final PriceChartRange initialRange;
  final double weightPct;
  final bool hasExplicitPeriod;
}

final class _TickerMoveData {
  _TickerMoveData({
    required this.ticker,
    required this.periodLabel,
    required this.changePct,
    required this.priceStart,
    required this.priceEnd,
    required this.weightPct,
  });

  factory _TickerMoveData.fromMap(JsonMap map) {
    return _TickerMoveData(
      ticker: GenUiHelpers.safeString(map['ticker'], defaultValue: ''),
      periodLabel: GenUiHelpers.safeString(
        map['periodLabel'],
        defaultValue: '',
      ),
      changePct: GenUiHelpers.safeDouble(map['changePct'], defaultValue: 0),
      priceStart: GenUiHelpers.safeDouble(map['priceStart'], defaultValue: 0),
      priceEnd: GenUiHelpers.safeDouble(map['priceEnd'], defaultValue: 0),
      weightPct: GenUiHelpers.safeDouble(map['weightPct'], defaultValue: 0),
    );
  }

  final String ticker;
  final String periodLabel;
  final double changePct;
  final double priceStart;
  final double priceEnd;
  final double weightPct;
}

final class _CompareItem {
  _CompareItem({required this.ticker, required this.changePct});

  final String ticker;
  final double changePct;
}

final class _CompareChartData {
  _CompareChartData({
    required this.tickers,
    required this.initialRange,
    required this.items,
  });

  factory _CompareChartData.fromMap(JsonMap map) {
    final items =
        GenUiHelpers.safeList(
          map['items'],
          defaultValue: const <_CompareItem>[],
          mapItem: (item) {
            final m = item as JsonMap;
            return _CompareItem(
              ticker:
                  GenUiHelpers.safeString(
                    m['ticker'],
                    defaultValue: '',
                  ).trim().toUpperCase(),
              changePct: GenUiHelpers.safeDouble(
                m['changePct'],
                defaultValue: 0,
              ),
            );
          },
        ).where((i) => i.ticker.isNotEmpty).take(3).toList();
    var tickers =
        GenUiHelpers.safeStringList(map['tickers'])
            .map((t) => t.trim().toUpperCase())
            .where((t) => t.isNotEmpty)
            .toSet()
            .take(3)
            .toList();
    if (tickers.isEmpty) tickers = [for (final i in items) i.ticker];
    return _CompareChartData(
      tickers: tickers,
      initialRange: PriceChartRange.fromWire(
        GenUiHelpers.safeString(map['initialRange'], defaultValue: ''),
      ),
      items: items,
    );
  }

  final List<String> tickers;
  final PriceChartRange initialRange;
  final List<_CompareItem> items;
}

final class _MetricItem {
  _MetricItem({required this.label, required this.value, required this.trend});

  factory _MetricItem.fromMap(JsonMap map) {
    return _MetricItem(
      label: GenUiHelpers.safeString(map['label'], defaultValue: ''),
      value: GenUiHelpers.safeString(map['value'], defaultValue: ''),
      trend: GenUiHelpers.safeEnum(map['trend'], const [
        'up',
        'down',
        'neutral',
      ], defaultValue: 'neutral'),
    );
  }

  final String label;
  final String value;
  final String trend;
}

final class _MetricStripData {
  _MetricStripData({required this.items, required this.periodLabel});

  factory _MetricStripData.fromMap(JsonMap map) {
    final items = GenUiHelpers.safeList(
      map['items'],
      defaultValue: const <_MetricItem>[],
      mapItem: (item) => _MetricItem.fromMap(item as JsonMap),
    );
    return _MetricStripData(
      items: items.take(3).toList(),
      periodLabel: GenUiHelpers.safeString(
        map['periodLabel'],
        defaultValue: '',
      ),
    );
  }

  final List<_MetricItem> items;
  final String periodLabel;
}

final class _ComparisonRowData {
  _ComparisonRowData({
    required this.label,
    required this.leftTicker,
    required this.leftValue,
    required this.rightTicker,
    required this.rightValue,
    required this.metricLabel,
  });

  factory _ComparisonRowData.fromMap(JsonMap map) {
    return _ComparisonRowData(
      label: GenUiHelpers.safeString(map['label'], defaultValue: ''),
      leftTicker: GenUiHelpers.safeString(map['leftTicker'], defaultValue: ''),
      leftValue: GenUiHelpers.safeString(map['leftValue'], defaultValue: ''),
      rightTicker: GenUiHelpers.safeString(
        map['rightTicker'],
        defaultValue: '',
      ),
      rightValue: GenUiHelpers.safeString(map['rightValue'], defaultValue: ''),
      metricLabel: GenUiHelpers.safeString(
        map['metricLabel'],
        defaultValue: '',
      ),
    );
  }

  final String label;
  final String leftTicker;
  final String leftValue;
  final String rightTicker;
  final String rightValue;
  final String metricLabel;
}
