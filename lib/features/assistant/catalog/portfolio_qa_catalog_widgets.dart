import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:intl/intl.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/shared/utils/genui_helpers.dart';

abstract final class PortfolioQaCatalogWidgets {
  static Widget qaAnswerText(CatalogItemContext ctx) {
    final data = _AnswerTextData.fromMap(ctx.data as JsonMap);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        data.text,
        style: const TextStyle(
          color: PortfolioColors.textPrimary,
          fontSize: 15,
          height: 1.45,
        ),
      ),
    );
  }

  static Widget qaMetricStrip(CatalogItemContext ctx) {
    final data = _MetricStripData.fromMap(ctx.data as JsonMap);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PortfolioColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: PortfolioColors.border.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < data.items.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 36,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: PortfolioColors.border,
              ),
            Expanded(child: _metricCell(data.items[i])),
          ],
        ],
      ),
    );
  }

  static Widget qaPeriodChange(CatalogItemContext ctx) {
    final data = _PeriodChangeData.fromMap(ctx.data as JsonMap);
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final isUp = data.changeAbs >= 0;
    final pnlColor = isUp ? PortfolioColors.profit : PortfolioColors.loss;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PortfolioColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: PortfolioColors.accentBlue.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.periodLabel,
            style: const TextStyle(
              color: PortfolioColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${isUp ? '+' : ''}${currency.format(data.changeAbs)} '
            '(${data.changePct.toStringAsFixed(1)}%)',
            style: TextStyle(
              color: pnlColor,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (data.valueStart > 0 && data.valueEnd > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${currency.format(data.valueStart)} → ${currency.format(data.valueEnd)}',
              style: const TextStyle(
                color: PortfolioColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget qaTickerMove(CatalogItemContext ctx) {
    final data = _TickerMoveData.fromMap(ctx.data as JsonMap);
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final isUp = data.changePct >= 0;
    final pnlColor = isUp ? PortfolioColors.profit : PortfolioColors.loss;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PortfolioColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: PortfolioColors.accentBlue.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                data.ticker,
                style: const TextStyle(
                  color: PortfolioColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (data.weightPct > 0)
                Text(
                  '${data.weightPct.toStringAsFixed(1)}% del portfolio',
                  style: const TextStyle(
                    color: PortfolioColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            data.periodLabel,
            style: const TextStyle(
              color: PortfolioColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${isUp ? '+' : ''}${data.changePct.toStringAsFixed(1)}%',
            style: TextStyle(
              color: pnlColor,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (data.priceStart > 0 && data.priceEnd > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${currency.format(data.priceStart)} → ${currency.format(data.priceEnd)}',
              style: const TextStyle(
                color: PortfolioColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget qaConcentrationBar(CatalogItemContext ctx) {
    final data = _ConcentrationBarData.fromMap(ctx.data as JsonMap);
    final maxWeight = data.items
        .map((e) => e.weightPct)
        .fold<double>(0, (a, b) => a > b ? a : b)
        .clamp(1, 100);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PortfolioColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                data.title,
                style: const TextStyle(
                  color: PortfolioColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          for (final item in data.items) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        item.ticker,
                        style: const TextStyle(
                          color: PortfolioColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${item.weightPct.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: PortfolioColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: item.weightPct / maxWeight,
                      minHeight: 6,
                      backgroundColor: PortfolioColors.border,
                      color: item.isHighlighted
                          ? PortfolioColors.accentBlue
                          : PortfolioColors.accentBlueDim,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget qaPnLBreakdown(CatalogItemContext ctx) {
    final data = _PnLBreakdownData.fromMap(ctx.data as JsonMap);
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final isUp = data.gainLoss >= 0;
    final pnlColor = isUp ? PortfolioColors.profit : PortfolioColors.loss;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PortfolioColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: _breakdownCell(
              label: 'Invertido',
              value: currency.format(data.costBasis),
            ),
          ),
          const Icon(
            Icons.arrow_forward,
            size: 14,
            color: PortfolioColors.textSecondary,
          ),
          Expanded(
            child: _breakdownCell(
              label: 'Valor actual',
              value: currency.format(data.currentValue),
              align: TextAlign.center,
            ),
          ),
          const Icon(
            Icons.arrow_forward,
            size: 14,
            color: PortfolioColors.textSecondary,
          ),
          Expanded(
            child: _breakdownCell(
              label: 'Resultado',
              value:
                  '${isUp ? '+' : ''}${currency.format(data.gainLoss)} (${data.gainLossPercent.toStringAsFixed(1)}%)',
              align: TextAlign.end,
              valueColor: pnlColor,
            ),
          ),
        ],
      ),
    );
  }

  static Widget qaTopMovers(CatalogItemContext ctx) {
    final data = _TopMoversData.fromMap(ctx.data as JsonMap);
    return Row(
      children: [
        Expanded(child: _moverCard(label: 'Mejor', mover: data.best)),
        const SizedBox(width: 8),
        Expanded(child: _moverCard(label: 'Peor', mover: data.worst)),
      ],
    );
  }

  static Widget qaPositionList(CatalogItemContext ctx) {
    final data = _PositionListData.fromMap(ctx.data as JsonMap);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: PortfolioColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (data.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Text(
                data.title,
                style: const TextStyle(
                  color: PortfolioColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          for (var i = 0; i < data.items.length; i++)
            _positionRow(
              data.items[i],
              showDivider: i < data.items.length - 1,
            ),
        ],
      ),
    );
  }

  static Widget qaClosedPositionList(CatalogItemContext ctx) {
    final data = _ClosedPositionListData.fromMap(ctx.data as JsonMap);
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: PortfolioColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (data.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Text(
                data.title,
                style: const TextStyle(
                  color: PortfolioColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          for (var i = 0; i < data.items.length; i++)
            _closedPositionRow(
              data.items[i],
              currency: currency,
              showDivider: i < data.items.length - 1,
            ),
        ],
      ),
    );
  }

  static Widget qaTipBanner(CatalogItemContext ctx) {
    final data = _TipBannerData.fromMap(ctx.data as JsonMap);
    final color = data.tone == 'warning'
        ? PortfolioColors.loss
        : PortfolioColors.accentBlue;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            data.tone == 'warning' ? Icons.info_outline : Icons.lightbulb_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              data.message,
              style: TextStyle(
                color: PortfolioColors.textPrimary.withValues(alpha: 0.9),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget qaComparisonRow(CatalogItemContext ctx) {
    final data = _ComparisonRowData.fromMap(ctx.data as JsonMap);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PortfolioColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.label,
            style: const TextStyle(
              color: PortfolioColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _comparisonCell(data.leftTicker, data.leftValue)),
              Container(
                width: 1,
                height: 40,
                color: PortfolioColors.border,
                margin: const EdgeInsets.symmetric(horizontal: 10),
              ),
              Expanded(
                child: _comparisonCell(
                  data.rightTicker,
                  data.rightValue,
                  align: TextAlign.end,
                ),
              ),
            ],
          ),
          if (data.metricLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                data.metricLabel,
                style: const TextStyle(
                  color: PortfolioColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Widget _metricCell(_MetricItem item) {
    final trendColor = switch (item.trend) {
      'up' => PortfolioColors.profit,
      'down' => PortfolioColors.loss,
      _ => PortfolioColors.textSecondary,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.label,
          style: const TextStyle(
            color: PortfolioColors.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Flexible(
              child: Text(
                item.value,
                style: const TextStyle(
                  color: PortfolioColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (item.trend != 'neutral') ...[
              const SizedBox(width: 4),
              Icon(
                item.trend == 'up' ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: trendColor,
              ),
            ],
          ],
        ),
      ],
    );
  }

  static Widget _breakdownCell({
    required String label,
    required String value,
    TextAlign align = TextAlign.start,
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: switch (align) {
        TextAlign.end => CrossAxisAlignment.end,
        TextAlign.center => CrossAxisAlignment.center,
        _ => CrossAxisAlignment.start,
      },
      children: [
        Text(
          label,
          textAlign: align,
          style: const TextStyle(
            color: PortfolioColors.textSecondary,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: align,
          style: TextStyle(
            color: valueColor ?? PortfolioColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  static Widget _moverCard({required String label, required _Mover mover}) {
    final isUp = mover.pnlPct >= 0;
    final color = isUp ? PortfolioColors.profit : PortfolioColors.loss;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: PortfolioColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: PortfolioColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            mover.ticker,
            style: const TextStyle(
              color: PortfolioColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '${isUp ? '+' : ''}${mover.pnlPct.toStringAsFixed(1)}%',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _closedPositionRow(
    _ClosedPositionItem item, {
    required NumberFormat currency,
    required bool showDivider,
  }) {
    final isUp = item.pnlPct >= 0;
    final pnlColor = isUp ? PortfolioColors.profit : PortfolioColors.loss;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.ticker,
                      style: const TextStyle(
                        color: PortfolioColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item.closeDateLabel.isNotEmpty)
                      Text(
                        item.closeDateLabel,
                        style: const TextStyle(
                          color: PortfolioColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isUp ? '+' : ''}${currency.format(item.pnlAbs)}',
                    style: TextStyle(
                      color: pnlColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${isUp ? '+' : ''}${item.pnlPct.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: pnlColor,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, color: PortfolioColors.border),
      ],
    );
  }

  static Widget _positionRow(_PositionItem item, {required bool showDivider}) {
    final isUp = item.pnlPct >= 0;
    final pnlColor = isUp ? PortfolioColors.profit : PortfolioColors.loss;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Text(
                item.ticker,
                style: const TextStyle(
                  color: PortfolioColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${item.weightPct.toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: PortfolioColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${isUp ? '+' : ''}${item.pnlPct.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: pnlColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            thickness: 1,
            color: PortfolioColors.border,
            indent: 12,
            endIndent: 12,
          ),
      ],
    );
  }

  static Widget _comparisonCell(
    String ticker,
    String value, {
    TextAlign align = TextAlign.start,
  }) {
    return Column(
      crossAxisAlignment: align == TextAlign.end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          ticker,
          style: const TextStyle(
            color: PortfolioColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: PortfolioColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

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
      periodLabel: GenUiHelpers.safeString(map['periodLabel'], defaultValue: ''),
      changeAbs: GenUiHelpers.safeDouble(map['changeAbs'], defaultValue: 0),
      changePct: GenUiHelpers.safeDouble(map['changePct'], defaultValue: 0),
      valueStart: GenUiHelpers.safeDouble(map['valueStart'], defaultValue: 0),
      valueEnd: GenUiHelpers.safeDouble(map['valueEnd'], defaultValue: 0),
    );
  }

  final String periodLabel;
  final double changeAbs;
  final double changePct;
  final double valueStart;
  final double valueEnd;
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
      periodLabel: GenUiHelpers.safeString(map['periodLabel'], defaultValue: ''),
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

final class _AnswerTextData {
  _AnswerTextData({required this.text});

  factory _AnswerTextData.fromMap(JsonMap map) {
    return _AnswerTextData(
      text: GenUiHelpers.safeString(map['text'], defaultValue: ''),
    );
  }

  final String text;
}

final class _MetricItem {
  _MetricItem({
    required this.label,
    required this.value,
    required this.trend,
  });

  factory _MetricItem.fromMap(JsonMap map) {
    return _MetricItem(
      label: GenUiHelpers.safeString(map['label'], defaultValue: ''),
      value: GenUiHelpers.safeString(map['value'], defaultValue: ''),
      trend: GenUiHelpers.safeEnum(
        map['trend'],
        const ['up', 'down', 'neutral'],
        defaultValue: 'neutral',
      ),
    );
  }

  final String label;
  final String value;
  final String trend;
}

final class _MetricStripData {
  _MetricStripData({required this.items});

  factory _MetricStripData.fromMap(JsonMap map) {
    final items = GenUiHelpers.safeList(
      map['items'],
      defaultValue: const <_MetricItem>[],
      mapItem: (item) => _MetricItem.fromMap(item as JsonMap),
    );
    return _MetricStripData(items: items.take(3).toList());
  }

  final List<_MetricItem> items;
}

final class _ConcentrationItem {
  _ConcentrationItem({
    required this.ticker,
    required this.weightPct,
    required this.isHighlighted,
  });

  factory _ConcentrationItem.fromMap(JsonMap map) {
    return _ConcentrationItem(
      ticker: GenUiHelpers.safeString(map['ticker'], defaultValue: ''),
      weightPct: GenUiHelpers.safeDouble(map['weightPct'], defaultValue: 0),
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
    final items = GenUiHelpers.safeList(
      map['items'],
      defaultValue: const <_ConcentrationItem>[],
      mapItem: (item) => _ConcentrationItem.fromMap(item as JsonMap),
    );
    return _ConcentrationBarData(
      title: GenUiHelpers.safeString(map['title'], defaultValue: ''),
      items: items.take(5).toList(),
    );
  }

  final String title;
  final List<_ConcentrationItem> items;
}

final class _PnLBreakdownData {
  _PnLBreakdownData({
    required this.costBasis,
    required this.currentValue,
    required this.gainLoss,
    required this.gainLossPercent,
  });

  factory _PnLBreakdownData.fromMap(JsonMap map) {
    return _PnLBreakdownData(
      costBasis: GenUiHelpers.safeDouble(map['costBasis'], defaultValue: 0),
      currentValue: GenUiHelpers.safeDouble(map['currentValue'], defaultValue: 0),
      gainLoss: GenUiHelpers.safeDouble(map['gainLoss'], defaultValue: 0),
      gainLossPercent:
          GenUiHelpers.safeDouble(map['gainLossPercent'], defaultValue: 0),
    );
  }

  final double costBasis;
  final double currentValue;
  final double gainLoss;
  final double gainLossPercent;
}

final class _Mover {
  _Mover({required this.ticker, required this.pnlPct});

  factory _Mover.fromMap(JsonMap map) {
    return _Mover(
      ticker: GenUiHelpers.safeString(map['ticker'], defaultValue: ''),
      pnlPct: GenUiHelpers.safeDouble(map['pnlPct'], defaultValue: 0),
    );
  }

  final String ticker;
  final double pnlPct;
}

final class _TopMoversData {
  _TopMoversData({required this.best, required this.worst});

  factory _TopMoversData.fromMap(JsonMap map) {
    return _TopMoversData(
      best: _Mover.fromMap(map['best'] as JsonMap? ?? {}),
      worst: _Mover.fromMap(map['worst'] as JsonMap? ?? {}),
    );
  }

  final _Mover best;
  final _Mover worst;
}

final class _PositionItem {
  _PositionItem({
    required this.ticker,
    required this.weightPct,
    required this.pnlPct,
  });

  factory _PositionItem.fromMap(JsonMap map) {
    return _PositionItem(
      ticker: GenUiHelpers.safeString(map['ticker'], defaultValue: ''),
      weightPct: GenUiHelpers.safeDouble(map['weightPct'], defaultValue: 0),
      pnlPct: GenUiHelpers.safeDouble(map['pnlPct'], defaultValue: 0),
    );
  }

  final String ticker;
  final double weightPct;
  final double pnlPct;
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
      ticker: GenUiHelpers.safeString(map['ticker'], defaultValue: ''),
      pnlPct: GenUiHelpers.safeDouble(map['pnlPct'], defaultValue: 0),
      pnlAbs: GenUiHelpers.safeDouble(map['pnlAbs'], defaultValue: 0),
      closeDateLabel:
          GenUiHelpers.safeString(map['closeDateLabel'], defaultValue: ''),
    );
  }

  final String ticker;
  final double pnlPct;
  final double pnlAbs;
  final String closeDateLabel;
}

final class _ClosedPositionListData {
  _ClosedPositionListData({required this.title, required this.items});

  factory _ClosedPositionListData.fromMap(JsonMap map) {
    final items = GenUiHelpers.safeList(
      map['items'],
      defaultValue: const <_ClosedPositionItem>[],
      mapItem: (item) => _ClosedPositionItem.fromMap(item as JsonMap),
    );
    return _ClosedPositionListData(
      title: GenUiHelpers.safeString(map['title'], defaultValue: ''),
      items: items.take(6).toList(),
    );
  }

  final String title;
  final List<_ClosedPositionItem> items;
}

final class _PositionListData {
  _PositionListData({required this.title, required this.items});

  factory _PositionListData.fromMap(JsonMap map) {
    final items = GenUiHelpers.safeList(
      map['items'],
      defaultValue: const <_PositionItem>[],
      mapItem: (item) => _PositionItem.fromMap(item as JsonMap),
    );
    return _PositionListData(
      title: GenUiHelpers.safeString(map['title'], defaultValue: ''),
      items: items.take(6).toList(),
    );
  }

  final String title;
  final List<_PositionItem> items;
}

final class _TipBannerData {
  _TipBannerData({required this.message, required this.tone});

  factory _TipBannerData.fromMap(JsonMap map) {
    return _TipBannerData(
      message: GenUiHelpers.safeString(map['message'], defaultValue: ''),
      tone: GenUiHelpers.safeEnum(
        map['tone'],
        const ['info', 'warning'],
        defaultValue: 'info',
      ),
    );
  }

  final String message;
  final String tone;
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
      rightTicker:
          GenUiHelpers.safeString(map['rightTicker'], defaultValue: ''),
      rightValue: GenUiHelpers.safeString(map['rightValue'], defaultValue: ''),
      metricLabel:
          GenUiHelpers.safeString(map['metricLabel'], defaultValue: ''),
    );
  }

  final String label;
  final String leftTicker;
  final String leftValue;
  final String rightTicker;
  final String rightValue;
  final String metricLabel;
}
