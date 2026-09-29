import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_history_use_case.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/reveal_step.dart';
import 'package:portfolio_assistant/features/assistant/services/price_chart_data_loader.dart';
import 'package:portfolio_assistant/shared/utils/genui_helpers.dart';
import 'package:portfolio_assistant/shared/utils/provider_lookup.dart';

/// Widgets del catálogo sobre el portfolio del usuario: totales, período,
/// concentración, movers y listas de posiciones abiertas/cerradas.
///
/// Todos toleran datos degenerados (0 o 1 posición, campos opcionales
/// ausentes, items mal formados): el modelo a veces manda payloads
/// parciales y una card vacía pero correcta es mejor que el error genérico.
abstract final class PortfolioWidgets {
  /// Hero del portfolio: valor total, P&L desde la compra y, si el modelo
  /// pasa `positions`, cómo se reparte el total entre las posiciones.
  static Widget qaPositionsSnapshot(CatalogItemContext ctx) {
    final data = _PositionsSnapshotData.fromMap(ctx.data as JsonMap);
    final count =
        data.positionsCount > 0 ? data.positionsCount : data.positions.length;
    final allocation = _allocationSlices(data.positions);

    return QaCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QaSectionLabel(
            'Tu portfolio',
            trailing:
                count > 0
                    ? QaTag(QaFormat.plural(count, 'posición', 'posiciones'))
                    : null,
          ),
          const SizedBox(height: 10),
          Text(QaFormat.money(data.totalValue), style: QaText.display),
          const SizedBox(height: 8),
          Row(
            children: [
              QaDeltaChip(
                value: data.pnlAbs,
                text:
                    '${QaFormat.money(data.pnlAbs.abs())} · '
                    '${QaFormat.pct(data.pnlPct.abs())}',
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'desde la compra',
                  style: QaText.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (allocation.isNotEmpty) ...[
            const SizedBox(height: QaSpace.sectionGap + 4),
            QaSegmentedBar(
              segments: [
                for (final s in allocation)
                  QaSegment(value: s.weightPct, color: s.color),
              ],
            ),
            const SizedBox(height: QaSpace.gap),
            Wrap(
              spacing: 14,
              runSpacing: 10,
              children: [for (final s in allocation) _AllocationLegend(s)],
            ),
          ],
          const QaFollowUpBar(
            items: [
              QaFollowUp(
                'Este mes',
                '¿Cuánto gané este mes?',
                icon: Icons.calendar_month_outlined,
              ),
              QaFollowUp(
                'Concentración',
                '¿Estoy muy concentrado?',
                icon: Icons.pie_chart_outline_rounded,
              ),
              QaFollowUp(
                'Movers de hoy',
                '¿Qué acciones se movieron más hoy?',
                icon: Icons.swap_vert_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Top 5 por peso + "Otros" con el resto: más de 5 colores en una barra
  /// fina ya no se distinguen.
  static List<_Slice> _allocationSlices(List<_WeightItem> positions) {
    final valid =
        positions.where((p) => p.ticker.isNotEmpty && p.weightPct > 0).toList()
          ..sort((a, b) => b.weightPct.compareTo(a.weightPct));
    if (valid.isEmpty) return const [];
    const maxShown = 5;
    final shown = valid.take(maxShown).toList();
    final rest = valid
        .skip(maxShown)
        .fold<double>(0, (sum, p) => sum + p.weightPct);
    return [
      for (var i = 0; i < shown.length; i++)
        _Slice(
          ticker: shown[i].ticker,
          weightPct: shown[i].weightPct,
          color: QaPalette.series(i),
        ),
      if (rest > 0.05)
        _Slice(ticker: null, weightPct: rest, color: _othersColor),
    ];
  }

  static final _othersColor = QaColors.textSecondary.withValues(alpha: 0.3);

  /// Cambio del portfolio completo en una ventana. El label del período
  /// aparece primero y el número después (reveal en dos etapas); la curva
  /// del período se carga del lado del cliente y, si no hay datos, la card
  /// queda igual de completa sin ella.
  static Widget qaPeriodChange(CatalogItemContext ctx) {
    final data = _PeriodChangeData.fromMap(ctx.data as JsonMap);
    final color =
        data.changeAbs == 0
            ? QaColors.textPrimary
            : QaPalette.trend(data.changeAbs);
    final hasRange = data.valueStart > 0 && data.valueEnd > 0;
    final label = data.periodLabel.isEmpty ? 'En el período' : data.periodLabel;

    final first = QaSectionLabel(label);
    final second = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                QaFormat.signedMoney(data.changeAbs),
                style: QaText.display.copyWith(color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            QaDeltaChip(value: data.changePct),
          ],
        ),
        _PortfolioPeriodSparkline(
          lookback: _lookbackFromLabel(data.periodLabel),
          color: QaPalette.trend(data.changeAbs),
        ),
        if (hasRange) ...[
          const SizedBox(height: QaSpace.gap),
          QaInset(
            child: Row(
              children: [
                Expanded(
                  child: QaStat(
                    label: 'Al inicio',
                    value: QaFormat.money(data.valueStart),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: QaColors.textSecondary,
                ),
                Expanded(
                  child: QaStat(
                    label: 'Ahora',
                    value: QaFormat.money(data.valueEnd),
                    crossAxisAlignment: CrossAxisAlignment.end,
                  ),
                ),
              ],
            ),
          ),
        ],
        QaFollowUpBar(
          items: [
            QaFollowUp(
              'Por qué',
              '¿Por qué se movió mi portfolio ${_inPeriod(data.periodLabel)}?',
              icon: Icons.help_outline_rounded,
            ),
            QaFollowUp(
              'Qué subió más',
              '¿Cuál de mis acciones subió más ${_inPeriod(data.periodLabel)}?',
              icon: Icons.swap_vert_rounded,
            ),
            const QaFollowUp(
              'Total',
              '¿Cómo está mi portfolio?',
              icon: Icons.account_balance_wallet_outlined,
            ),
          ],
        ),
      ],
    );

    return QaCardShell.staged(
      staged:
          (context, active, onFinished) => TwoStageReveal(
            active: active,
            first: first,
            second: second,
            onFinished: onFinished,
          ),
    );
  }

  /// "últimos 30 días" → "en los últimos 30 días", para armar preguntas
  /// naturales con el label que copia el modelo de `label_es`.
  static String _inPeriod(String label) {
    final l = label.trim().toLowerCase();
    if (l.isEmpty) return 'en este período';
    if (l.startsWith('últimos ') || l.startsWith('ultimos ')) {
      return 'en los $l';
    }
    if (l.startsWith('último ') || l.startsWith('ultimo ')) {
      return 'en el $l';
    }
    if (l.startsWith('est') || l.startsWith('hoy') || l.startsWith('en ')) {
      return l;
    }
    return 'en $l';
  }

  /// Ventana del período a partir del label (los `label_es` del tool son un
  /// set chico y fijo). `null` → sin curva: la del día no tiene resolución
  /// con cierres diarios, y un label desconocido no se adivina.
  static Duration? _lookbackFromLabel(String label) {
    final l = label.toLowerCase();
    final days = int.tryParse(
      RegExp(r'(\d+)\s*d[ií]as').firstMatch(l)?[1] ?? '',
    );
    if (days != null && days >= 5) return Duration(days: days);
    if (l.contains('semana')) return const Duration(days: 7);
    if (l.contains('trimestre')) return const Duration(days: 90);
    if (l.contains('mes')) return const Duration(days: 30);
    if (l.contains('año')) return const Duration(days: 365);
    return null;
  }

  /// Concentración por activo: donut con el peso de la mayor posición al
  /// centro + leyenda con barras. La severidad sale del peso de la mayor
  /// (es lo único confiable: `items` viene recortado a 5).
  static Widget qaConcentrationBar(CatalogItemContext ctx) {
    final data = _ConcentrationBarData.fromMap(ctx.data as JsonMap);
    final items = data.items;
    final anyHighlighted = items.any((e) => e.isHighlighted);
    final top = items.isEmpty ? null : items.first;
    final covered = items.fold<double>(0, (a, e) => a + e.weightPct);
    final rest = math.max(0.0, 100 - covered);

    Color colorFor(int i) {
      final base = QaPalette.series(i);
      if (!anyHighlighted || items[i].isHighlighted) return base;
      return base.withValues(alpha: 0.4);
    }

    final severity = _concentrationSeverity(top?.weightPct ?? 0);
    return QaCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QaCardTitle(
            title: data.title.isEmpty ? 'Concentración' : data.title,
            icon: Icons.pie_chart_outline_rounded,
            trailing: items.isEmpty ? null : severity,
          ),
          const SizedBox(height: QaSpace.sectionGap),
          if (top == null)
            Text(
              'No hay posiciones para medir la concentración.',
              style: QaText.label,
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                QaDonut(
                  size: 104,
                  stroke: 12,
                  segments: [
                    for (var i = 0; i < items.length; i++)
                      QaSegment(value: items[i].weightPct, color: colorFor(i)),
                    if (rest > 0.5) QaSegment(value: rest, color: _othersColor),
                  ],
                  center: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        QaFormat.pct(
                          top.weightPct,
                          digits: top.weightPct >= 10 ? 0 : 1,
                        ),
                        style: QaText.displaySm.copyWith(fontSize: 20),
                      ),
                      Text(top.ticker, style: QaText.caption),
                    ],
                  ),
                ),
                const SizedBox(width: QaSpace.sectionGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        _ConcentrationRow(
                          item: items[i],
                          color: colorFor(i),
                          emphasized: !anyHighlighted || items[i].isHighlighted,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          const QaFollowUpBar(
            items: [
              QaFollowUp(
                'Diversificar',
                '¿Cómo puedo diversificar?',
                icon: Icons.call_split_rounded,
              ),
              QaFollowUp(
                'Mis posiciones',
                '¿Qué posiciones tengo?',
                icon: Icons.list_alt_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Umbrales de referencia comunes: una sola posición ≥ 40% domina el
  /// riesgo del portfolio; < 25% ya es un reparto razonable.
  static Widget _concentrationSeverity(double topWeight) {
    if (topWeight >= 40) {
      return QaTag(
        'Alta concentración',
        color: QaColors.accentBlue,
        icon: Icons.error_outline_rounded,
      );
    }
    if (topWeight >= 25) return const QaTag('Concentración moderada');
    return QaTag('Bien repartido', color: QaColors.profit);
  }

  /// Invertido → valor actual → resultado, como una barra: el tramo neutro
  /// es lo que se conserva del capital y el tramo de color es la ganancia
  /// (o lo que se perdió, sobre el total invertido).
  static Widget qaPnLBreakdown(CatalogItemContext ctx) {
    final data = _PnLBreakdownData.fromMap(ctx.data as JsonMap);
    final gain = data.gainLoss;
    final trend = QaPalette.trend(gain);
    final kept = math.max(0.0, math.min(data.costBasis, data.currentValue));
    final delta = gain.abs();
    final neutral = QaColors.textPrimary.withValues(alpha: 0.75);

    return QaCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QaSectionLabel(data.title.isEmpty ? 'Resultado' : data.title),
          const SizedBox(height: 10),
          Row(
            children: [
              Flexible(
                child: Text(
                  QaFormat.signedMoney(gain),
                  style: QaText.display.copyWith(
                    color: gain == 0 ? QaColors.textPrimary : trend,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              QaDeltaChip(value: data.gainLossPercent),
            ],
          ),
          const SizedBox(height: QaSpace.sectionGap + 2),
          QaSegmentedBar(
            height: 12,
            segments: [
              QaSegment(value: kept, color: neutral),
              if (delta > 0)
                QaSegment(
                  value: delta,
                  color:
                      gain >= 0 ? trend : QaColors.loss.withValues(alpha: 0.35),
                ),
            ],
          ),
          const SizedBox(height: QaSpace.gap),
          Row(
            children: [
              Expanded(
                child: _LegendStat(
                  color: neutral,
                  label: 'Invertido',
                  value: QaFormat.money(data.costBasis),
                ),
              ),
              Expanded(
                child: _LegendStat(
                  color:
                      gain >= 0 ? trend : QaColors.loss.withValues(alpha: 0.35),
                  label: gain >= 0 ? 'Ganancia' : 'Pérdida',
                  value: QaFormat.money(delta),
                ),
              ),
              Expanded(
                child: QaStat(
                  label: 'Valor actual',
                  value: QaFormat.money(data.currentValue),
                  crossAxisAlignment: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
          const QaFollowUpBar(
            items: [
              QaFollowUp(
                'Este mes',
                '¿Cuánto gané este mes?',
                icon: Icons.calendar_month_outlined,
              ),
              QaFollowUp(
                'Mejor posición',
                '¿Cuál es mi mejor posición?',
                icon: Icons.emoji_events_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Mejor y peor posición en una sola card: dos tiles tocables con la
  /// curva de la semana (o de la ventana pedida) cargada del lado del
  /// cliente. Con un solo ticker válido queda un único tile.
  static Widget qaTopMovers(CatalogItemContext ctx) {
    final data = _TopMoversData.fromMap(ctx.data as JsonMap);
    final metricLabel =
        data.best.isPeriodChange || data.worst.isPeriodChange
            ? (data.periodLabel.isEmpty
                ? 'Variación del período'
                : 'Variación · ${data.periodLabel}')
            : 'Rendimiento total';
    final range =
        data.best.isPeriodChange
            ? _rangeFromLabel(data.periodLabel)
            : PriceChartRange.week;
    // Con P&L total la curva es de otra métrica (la última semana): se
    // dibuja neutra para no contradecir el color del chip.
    final neutralSpark = !data.best.isPeriodChange;

    final showWorst =
        data.worst.ticker.isNotEmpty && data.worst.ticker != data.best.ticker;
    final tiles = [
      if (data.best.ticker.isNotEmpty)
        _MoverTile(
          label: 'Mejor',
          mover: data.best,
          range: range,
          neutralSpark: neutralSpark,
        ),
      if (showWorst)
        _MoverTile(
          label: 'Peor',
          mover: data.worst,
          range: range,
          neutralSpark: neutralSpark,
        ),
    ];

    return QaCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QaSectionLabel(metricLabel),
          const SizedBox(height: QaSpace.gap),
          if (tiles.isEmpty)
            Text('No hay posiciones para comparar.', style: QaText.label)
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: tiles[i]),
                ],
              ],
            ),
          QaFollowUpBar(
            items: [
              if (data.best.ticker.isNotEmpty)
                _whyFollowUp(data.best.ticker, data.best.value),
              if (showWorst) _whyFollowUp(data.worst.ticker, data.worst.value),
              const QaFollowUp(
                'Mis posiciones',
                '¿Qué posiciones tengo?',
                icon: Icons.list_alt_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static QaFollowUp _whyFollowUp(String ticker, double value) => QaFollowUp(
    'Por qué $ticker',
    value >= 0 ? '¿Por qué subió $ticker?' : '¿Por qué bajó $ticker?',
    icon: Icons.help_outline_rounded,
  );

  static PriceChartRange _rangeFromLabel(String label) {
    final lookback = _lookbackFromLabel(label);
    if (lookback == null) {
      return label.toLowerCase().contains('día') ||
              label.toLowerCase().contains('hoy')
          ? PriceChartRange.day
          : PriceChartRange.week;
    }
    final days = lookback.inDays;
    if (days <= 7) return PriceChartRange.week;
    if (days <= 30) return PriceChartRange.month;
    if (days <= 90) return PriceChartRange.quarter;
    return PriceChartRange.year;
  }

  static Widget qaPositionList(CatalogItemContext ctx) {
    final data = _PositionListData.fromMap(ctx.data as JsonMap);
    final items = data.items;
    return QaCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QaCardTitle(
            title: data.title.isEmpty ? 'Tus posiciones' : data.title,
            icon: Icons.account_balance_wallet_outlined,
            trailing:
                items.isEmpty
                    ? null
                    : QaTag(
                      QaFormat.plural(items.length, 'posición', 'posiciones'),
                    ),
          ),
          const SizedBox(height: 6),
          if (items.isEmpty)
            const _EmptyState(
              icon: Icons.inbox_outlined,
              title: 'No tenés posiciones abiertas',
              body: 'Cuando cargues una compra, la vas a ver acá.',
            )
          else
            _ExpandableRows(
              rows: [for (final item in items) _PositionRow(item)],
            ),
          if (items.isNotEmpty)
            QaFollowUpBar(
              items: [
                const QaFollowUp(
                  'Concentración',
                  '¿Estoy muy concentrado?',
                  icon: Icons.pie_chart_outline_rounded,
                ),
                if (items.length > 1)
                  const QaFollowUp(
                    'Mejor posición',
                    '¿Cuál es mi mejor posición?',
                    icon: Icons.emoji_events_outlined,
                  ),
                const QaFollowUp(
                  'Total',
                  '¿Cómo está mi portfolio?',
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ],
            ),
        ],
      ),
    );
  }

  static Widget qaClosedPositionList(CatalogItemContext ctx) {
    final data = _ClosedPositionListData.fromMap(ctx.data as JsonMap);
    final items = data.items;
    final total = data.totalPnlAbs;

    return QaCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QaCardTitle(
            title: data.title.isEmpty ? 'Posiciones cerradas' : data.title,
            icon: Icons.task_alt_rounded,
            trailing:
                items.isEmpty
                    ? null
                    : QaTag(
                      QaFormat.plural(items.length, 'operación', 'operaciones'),
                    ),
          ),
          if (total != null && items.isNotEmpty) ...[
            const SizedBox(height: QaSpace.gap),
            QaInset(
              child: Row(
                children: [
                  Expanded(
                    child: QaStat(
                      label: 'Resultado realizado',
                      value: QaFormat.signedMoney(total),
                      valueColor: total == 0 ? null : QaPalette.trend(total),
                      large: true,
                    ),
                  ),
                  if (data.totalPnlPct != null)
                    QaDeltaChip(value: data.totalPnlPct!),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          if (items.isEmpty)
            const _EmptyState(
              icon: Icons.history_rounded,
              title: 'Todavía no cerraste posiciones',
              body:
                  'Cuando vendas una posición, vas a ver acá cuánto ganaste '
                  'o perdiste.',
            )
          else
            _ExpandableRows(
              rows: [for (final item in items) _ClosedPositionRow(item)],
            ),
          if (items.isNotEmpty)
            const QaFollowUpBar(
              items: [
                QaFollowUp(
                  'Mejor operación',
                  '¿Cuál fue mi mejor operación cerrada?',
                  icon: Icons.emoji_events_outlined,
                ),
                QaFollowUp(
                  'Abiertas',
                  '¿Qué posiciones tengo?',
                  icon: Icons.list_alt_rounded,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ─── Piezas de UI ──────────────────────────────────────────────────────────

final class _Slice {
  const _Slice({
    required this.ticker,
    required this.weightPct,
    required this.color,
  });

  /// `null` = "Otros".
  final String? ticker;
  final double weightPct;
  final Color color;
}

class _ColorDot extends StatelessWidget {
  const _ColorDot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _AllocationLegend extends StatelessWidget {
  const _AllocationLegend(this.slice);
  final _Slice slice;

  @override
  Widget build(BuildContext context) {
    final ticker = slice.ticker;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ColorDot(slice.color),
        const SizedBox(width: 6),
        if (ticker != null) ...[
          QaTickerAvatar(ticker: ticker, size: 20),
          const SizedBox(width: 6),
        ],
        Text(ticker ?? 'Otros', style: QaText.valueSm),
        const SizedBox(width: 4),
        Text(QaFormat.pct(slice.weightPct), style: QaText.caption),
      ],
    );
  }
}

/// Punto de color + rótulo + valor: stat con referencia al tramo de una
/// barra apilada.
class _LegendStat extends StatelessWidget {
  const _LegendStat({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _ColorDot(color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: QaText.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(value, style: QaText.value, maxLines: 1),
      ],
    );
  }
}

class _ConcentrationRow extends StatelessWidget {
  const _ConcentrationRow({
    required this.item,
    required this.color,
    required this.emphasized,
  });

  final _ConcentrationItem item;
  final Color color;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return QaTappable(
      question: '¿Cómo me va con ${item.ticker}?',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  // Punto del color del segmento: el vínculo leyenda↔donut
                  // sin depender de que la barra de abajo se note.
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  QaTickerAvatar(ticker: item.ticker, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.ticker,
                      style: (emphasized ? QaText.bodyStrong : QaText.body)
                          .copyWith(
                            fontSize: 13,
                            color:
                                emphasized
                                    ? QaColors.textPrimary
                                    : QaColors.textSecondary,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    QaFormat.pct(item.weightPct),
                    style: QaText.valueSm.copyWith(
                      color:
                          emphasized
                              ? QaColors.textPrimary
                              : QaColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              QaProgressBar(
                value: item.weightPct / 100,
                color: color,
                height: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoverTile extends StatelessWidget {
  const _MoverTile({
    required this.label,
    required this.mover,
    required this.range,
    required this.neutralSpark,
  });

  final String label;
  final _Mover mover;
  final PriceChartRange range;
  final bool neutralSpark;

  @override
  Widget build(BuildContext context) {
    return QaTappable(
      question: '¿Cómo viene ${mover.ticker}?',
      child: QaInset(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: QaText.label),
            const SizedBox(height: 8),
            Row(
              children: [
                QaTickerAvatar(ticker: mover.ticker, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mover.ticker,
                    style: QaText.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: QaDeltaChip(value: mover.value, digits: 1),
            ),
            const SizedBox(height: 10),
            _TickerSparkline(
              ticker: mover.ticker,
              range: range,
              color:
                  neutralSpark
                      ? QaColors.textSecondary.withValues(alpha: 0.7)
                      : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _PositionRow extends StatelessWidget {
  const _PositionRow(this.item);
  final _PositionItem item;

  @override
  Widget build(BuildContext context) {
    final weight = QaFormat.pct(item.weightPct);
    return QaTappable(
      question: '¿Cómo me va con ${item.ticker}?',
      child: QaBrandBuilder(
        ticker: item.ticker,
        builder: (context, brand) {
          final name = brand.name;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                QaTickerAvatar(ticker: item.ticker, brand: brand, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(item.ticker, style: QaText.title),
                      Text(
                        name == null || name.isEmpty
                            ? '$weight del portfolio'
                            : '$name · $weight',
                        style: QaText.label,
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
                    if (item.marketValue != null) ...[
                      Text(
                        QaFormat.money(item.marketValue!),
                        style: QaText.value,
                      ),
                      const SizedBox(height: 4),
                    ],
                    QaDeltaChip(value: item.pnlPct, digits: 1, dense: true),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ClosedPositionRow extends StatelessWidget {
  const _ClosedPositionRow(this.item);
  final _ClosedPositionItem item;

  @override
  Widget build(BuildContext context) {
    return QaTappable(
      question: '¿Cómo me fue con ${item.ticker}?',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            QaTickerAvatar(ticker: item.ticker, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.ticker, style: QaText.title),
                  Text(
                    item.closeDateLabel.isEmpty
                        ? 'Cerrada'
                        : 'Cerrada el ${item.closeDateLabel}',
                    style: QaText.label,
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
                Text(
                  QaFormat.signedMoney(item.pnlAbs),
                  style: QaText.value.copyWith(
                    color:
                        item.pnlAbs == 0
                            ? QaColors.textPrimary
                            : QaPalette.trend(item.pnlAbs),
                  ),
                ),
                const SizedBox(height: 4),
                QaDeltaChip(value: item.pnlPct, digits: 1, dense: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: QaSpace.gap),
      child: QaInset(
        padding: const EdgeInsets.all(QaSpace.cardPadding),
        child: Row(
          children: [
            Icon(icon, size: 22, color: QaColors.textSecondary),
            const SizedBox(width: QaSpace.gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: QaText.bodyStrong),
                  const SizedBox(height: 2),
                  Text(body, style: QaText.label),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Filas con divisores; más de [limit] + 1 → muestra [limit] y un toggle
/// local "Ver todas (n)". (Con exactamente una de más no vale la pena
/// esconderla detrás de un tap.)
class _ExpandableRows extends StatefulWidget {
  const _ExpandableRows({required this.rows});

  static const limit = 5;
  final List<Widget> rows;

  @override
  State<_ExpandableRows> createState() => _ExpandableRowsState();
}

class _ExpandableRowsState extends State<_ExpandableRows> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final collapsible = rows.length > _ExpandableRows.limit + 1;
    final visible =
        collapsible && !_expanded ? rows.take(_ExpandableRows.limit) : rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, row) in visible.indexed) ...[
          if (i > 0) const QaDivider(),
          row,
        ],
        if (collapsible) ...[
          const QaDivider(),
          QaTappable(
            onTap: () => setState(() => _expanded = !_expanded),
            child: SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _expanded ? 'Ver menos' : 'Ver todas (${rows.length})',
                    style: QaText.bodyStrong.copyWith(
                      fontSize: 13,
                      color: QaColors.accentBlue,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: QaColors.accentBlue,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Curva de precio de un ticker para un tile, cargada con el mismo loader
/// que `QaPriceChart`. Reserva siempre su alto: los dos tiles de
/// `QaTopMovers` quedan parejos haya o no datos. Sin loader o sin datos,
/// queda el hueco en blanco (degrada en silencio).
class _TickerSparkline extends StatefulWidget {
  const _TickerSparkline({
    required this.ticker,
    required this.range,
    this.color,
  });

  final String ticker;
  final PriceChartRange range;
  final Color? color;

  static const height = 28.0;

  /// Por sesión: la misma card se reconstruye al hacer scroll y varias
  /// respuestas repiten tickers.
  static final _cache = <String, List<double>?>{};

  @override
  State<_TickerSparkline> createState() => _TickerSparklineState();
}

class _TickerSparklineState extends State<_TickerSparkline> {
  List<double>? _values;
  bool _requested = false;

  String get _key => '${widget.ticker}|${widget.range.wireValue}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested || widget.ticker.isEmpty) return;
    _requested = true;
    if (_TickerSparkline._cache.containsKey(_key)) {
      _values = _TickerSparkline._cache[_key];
      return;
    }
    final loader = readProviderOrNull(context, priceChartDataLoaderProvider);
    if (loader == null) return;
    unawaited(_load(loader));
  }

  Future<void> _load(PriceChartDataLoader loader) async {
    List<double>? values;
    try {
      final candles = await loader.load(widget.ticker, widget.range);
      values = candles?.map((c) => c.close).toList();
    } catch (_) {
      values = null;
    }
    _TickerSparkline._cache[_key] = values;
    if (mounted && values != null) setState(() => _values = values);
  }

  @override
  Widget build(BuildContext context) {
    final values = _values;
    return SizedBox(
      height: _TickerSparkline.height,
      child:
          values == null || values.length < 2
              ? null
              : LayoutBuilder(
                builder:
                    (context, c) => QaSparkline(
                      values: values,
                      width: c.maxWidth,
                      height: _TickerSparkline.height,
                      color: widget.color,
                    ),
              ),
    );
  }
}

/// Curva del valor del portfolio en la ventana de `QaPeriodChange`, desde
/// el mismo histórico que usa la home (`GetPortfolioHistoryUseCase`). Es
/// solo visual: el número de la card sigue siendo el del tool. Sin datos
/// suficientes no ocupa lugar.
class _PortfolioPeriodSparkline extends StatefulWidget {
  const _PortfolioPeriodSparkline({
    required this.lookback,
    required this.color,
  });

  final Duration? lookback;
  final Color color;

  /// El histórico es caro (posiciones + diarios por ticker): se comparte
  /// entre cards por unos minutos.
  static const _ttl = Duration(minutes: 5);
  static DateTime? _fetchedAt;
  static Future<List<PortfolioHistoryPoint>?>? _pending;

  @override
  State<_PortfolioPeriodSparkline> createState() =>
      _PortfolioPeriodSparklineState();
}

class _PortfolioPeriodSparklineState extends State<_PortfolioPeriodSparkline> {
  List<double>? _values;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested || widget.lookback == null) return;
    _requested = true;
    // El sparkline es decorativo: si armar el provider falla (p. ej. un
    // backend sin inicializar), la card sigue sin curva en vez de romperse.
    final GetPortfolioHistoryUseCase? useCase;
    try {
      useCase = readProviderOrNull(context, getPortfolioHistoryUseCaseProvider);
    } catch (_) {
      return;
    }
    if (useCase == null) return;

    final fetchedAt = _PortfolioPeriodSparkline._fetchedAt;
    final stale =
        fetchedAt == null ||
        DateTime.now().difference(fetchedAt) > _PortfolioPeriodSparkline._ttl;
    if (stale || _PortfolioPeriodSparkline._pending == null) {
      _PortfolioPeriodSparkline._fetchedAt = DateTime.now();
      _PortfolioPeriodSparkline._pending = useCase().then(
        (result) => result.fold((_) => null, (points) => points),
        onError: (_) => null,
      );
    }
    unawaited(
      _PortfolioPeriodSparkline._pending!.then((points) {
        final values = _window(points);
        if (mounted && values != null) setState(() => _values = values);
      }),
    );
  }

  List<double>? _window(List<PortfolioHistoryPoint>? points) {
    if (points == null || points.length < 3) return null;
    final cutoff = points.last.date.subtract(widget.lookback!);
    final values = [
      for (final p in points)
        if (!p.date.isBefore(cutoff)) p.totalValue,
    ];
    return values.length < 3 ? null : values;
  }

  @override
  Widget build(BuildContext context) {
    final values = _values;
    if (values == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: QaSpace.sectionGap),
      child: LayoutBuilder(
        builder:
            (context, c) => QaSparkline(
              values: values,
              width: c.maxWidth,
              height: 56,
              color: widget.color,
            ),
      ),
    );
  }
}

// ─── Parseo ────────────────────────────────────────────────────────────────

/// Items de una lista como mapas, descartando lo que no lo sea (un string
/// suelto en `items` no debería tirar abajo la card entera).
List<JsonMap> _maps(Object? value) => [
  if (value is List)
    for (final e in value)
      if (e is Map) e.map((k, v) => MapEntry(k.toString(), v)),
];

double? _optDouble(Object? value) {
  if (value == null) return null;
  final d = GenUiHelpers.safeDouble(value, defaultValue: double.nan);
  return d.isFinite ? d : null;
}

double _double(Object? value) => _optDouble(value) ?? 0;

String _string(Object? value) =>
    GenUiHelpers.safeString(value, defaultValue: '').trim();

final class _PeriodChangeData {
  _PeriodChangeData({
    required this.periodLabel,
    required this.changeAbs,
    required this.changePct,
    required this.valueStart,
    required this.valueEnd,
  });

  factory _PeriodChangeData.fromMap(JsonMap map) {
    return _PeriodChangeData(
      periodLabel: _string(map['periodLabel']),
      changeAbs: _double(map['changeAbs']),
      changePct: _double(map['changePct']),
      valueStart: _double(map['valueStart']),
      valueEnd: _double(map['valueEnd']),
    );
  }

  final String periodLabel;
  final double changeAbs;
  final double changePct;
  final double valueStart;
  final double valueEnd;
}

final class _ConcentrationItem {
  _ConcentrationItem({
    required this.ticker,
    required this.weightPct,
    required this.isHighlighted,
  });

  factory _ConcentrationItem.fromMap(JsonMap map) {
    return _ConcentrationItem(
      ticker: _string(map['ticker']),
      weightPct: _double(map['weightPct']).clamp(0, 100).toDouble(),
      isHighlighted: GenUiHelpers.safeBool(
        map['isHighlighted'],
        defaultValue: false,
      ),
    );
  }

  final String ticker;
  final double weightPct;
  final bool isHighlighted;
}

final class _ConcentrationBarData {
  _ConcentrationBarData({required this.title, required this.items});

  factory _ConcentrationBarData.fromMap(JsonMap map) {
    // Ordenado por peso: el donut y la severidad asumen que el primero es
    // la mayor posición, aunque el modelo las mande en otro orden.
    final items =
        _maps(map['items'])
            .map(_ConcentrationItem.fromMap)
            .where((e) => e.ticker.isNotEmpty)
            .toList()
          ..sort((a, b) => b.weightPct.compareTo(a.weightPct));
    return _ConcentrationBarData(
      title: _string(map['title']),
      items: items.take(5).toList(),
    );
  }

  final String title;
  final List<_ConcentrationItem> items;
}

final class _PnLBreakdownData {
  _PnLBreakdownData({
    required this.title,
    required this.costBasis,
    required this.currentValue,
    required this.gainLoss,
    required this.gainLossPercent,
  });

  factory _PnLBreakdownData.fromMap(JsonMap map) {
    return _PnLBreakdownData(
      title: _string(map['title']),
      costBasis: _double(map['costBasis']),
      currentValue: _double(map['currentValue']),
      gainLoss: _double(map['gainLoss']),
      gainLossPercent: _double(map['gainLossPercent']),
    );
  }

  final String title;
  final double costBasis;
  final double currentValue;
  final double gainLoss;
  final double gainLossPercent;
}

final class _Mover {
  _Mover({required this.ticker, required this.pnlPct, required this.changePct});

  factory _Mover.fromMap(JsonMap map) {
    return _Mover(
      ticker: _string(map['ticker']),
      pnlPct: _optDouble(map['pnlPct']),
      changePct: _optDouble(map['changePct']),
    );
  }

  final String ticker;

  /// Rendimiento total desde la compra (P&L %).
  final double? pnlPct;

  /// Variación de precio dentro de una ventana (ver `periodLabel`).
  final double? changePct;

  bool get isPeriodChange => changePct != null;
  double get value => changePct ?? pnlPct ?? 0;
}

final class _TopMoversData {
  _TopMoversData({
    required this.best,
    required this.worst,
    required this.periodLabel,
  });

  factory _TopMoversData.fromMap(JsonMap map) {
    JsonMap mover(Object? v) {
      final list = _maps([v]);
      return list.isEmpty ? const {} : list.first;
    }

    return _TopMoversData(
      best: _Mover.fromMap(mover(map['best'])),
      worst: _Mover.fromMap(mover(map['worst'])),
      periodLabel: _string(map['periodLabel']),
    );
  }

  final _Mover best;
  final _Mover worst;
  final String periodLabel;
}

final class _WeightItem {
  const _WeightItem({required this.ticker, required this.weightPct});

  factory _WeightItem.fromMap(JsonMap map) => _WeightItem(
    ticker: _string(map['ticker']),
    weightPct: _double(map['weightPct']),
  );

  final String ticker;
  final double weightPct;
}

final class _PositionsSnapshotData {
  _PositionsSnapshotData({
    required this.totalValue,
    required this.pnlAbs,
    required this.pnlPct,
    required this.positionsCount,
    required this.positions,
  });

  factory _PositionsSnapshotData.fromMap(JsonMap map) {
    return _PositionsSnapshotData(
      totalValue: _double(map['totalValue']),
      pnlAbs: _double(map['pnlAbs']),
      pnlPct: _double(map['pnlPct']),
      positionsCount: GenUiHelpers.safeInt(
        map['positionsCount'],
        defaultValue: 0,
      ),
      positions: _maps(map['positions']).map(_WeightItem.fromMap).toList(),
    );
  }

  final double totalValue;
  final double pnlAbs;
  final double pnlPct;
  final int positionsCount;
  final List<_WeightItem> positions;
}

final class _PositionItem {
  _PositionItem({
    required this.ticker,
    required this.weightPct,
    required this.pnlPct,
    required this.marketValue,
  });

  factory _PositionItem.fromMap(JsonMap map) {
    return _PositionItem(
      ticker: _string(map['ticker']),
      weightPct: _double(map['weightPct']),
      pnlPct: _double(map['pnlPct']),
      marketValue: _optDouble(map['marketValue']),
    );
  }

  final String ticker;
  final double weightPct;
  final double pnlPct;
  final double? marketValue;
}

final class _PositionListData {
  _PositionListData({required this.title, required this.items});

  factory _PositionListData.fromMap(JsonMap map) {
    return _PositionListData(
      title: _string(map['title']),
      items:
          _maps(map['items'])
              .map(_PositionItem.fromMap)
              .where((e) => e.ticker.isNotEmpty)
              .take(20)
              .toList(),
    );
  }

  final String title;
  final List<_PositionItem> items;
}

final class _ClosedPositionItem {
  _ClosedPositionItem({
    required this.ticker,
    required this.pnlPct,
    required this.pnlAbs,
    required this.closeDateLabel,
  });

  factory _ClosedPositionItem.fromMap(JsonMap map) {
    return _ClosedPositionItem(
      ticker: _string(map['ticker']),
      pnlPct: _double(map['pnlPct']),
      pnlAbs: _double(map['pnlAbs']),
      closeDateLabel: _string(map['closeDateLabel']),
    );
  }

  final String ticker;
  final double pnlPct;
  final double pnlAbs;
  final String closeDateLabel;
}

final class _ClosedPositionListData {
  _ClosedPositionListData({
    required this.title,
    required this.items,
    required this.totalPnlAbs,
    required this.totalPnlPct,
  });

  factory _ClosedPositionListData.fromMap(JsonMap map) {
    return _ClosedPositionListData(
      title: _string(map['title']),
      items:
          _maps(map['items'])
              .map(_ClosedPositionItem.fromMap)
              .where((e) => e.ticker.isNotEmpty)
              .take(20)
              .toList(),
      totalPnlAbs: _optDouble(map['totalPnlAbs']),
      totalPnlPct: _optDouble(map['totalPnlPct']),
    );
  }

  final String title;
  final List<_ClosedPositionItem> items;
  final double? totalPnlAbs;
  final double? totalPnlPct;
}
