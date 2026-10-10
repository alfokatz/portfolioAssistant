import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/assistant/data/market/dividend_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/buy_plan_builder.dart';
import 'package:portfolio_assistant/features/assistant/tools/advice_tools.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

/// La card de la compra mensual: qué comprar cada mes y cuánto a cada uno.
///
/// El modelo solo pasa `buyPlanId`: todo sale del resultado de
/// `get_monthly_buy_plan` (montos, porcentajes y rendimientos reales).
abstract final class BuyPlanWidgets {
  static Widget qaBuyPlan(CatalogItemContext ctx) {
    final id = '${(ctx.data as JsonMap)['buyPlanId'] ?? ''}';
    return Builder(
      builder:
          (context) => ValueListenableBuilder(
            valueListenable: QaEvidenceScope.listenableOf(
              context,
              ctx.surfaceId,
            ),
            builder: (context, evidence, _) {
              final data = BuyPlanCardData.from(evidence.calls, id);
              if (data == null) return const SizedBox.shrink();
              return QaCardShell(child: QaBuyPlanCard(data: data));
            },
          ),
    );
  }
}

class BuyPlanItem {
  const BuyPlanItem({
    required this.ticker,
    required this.kind,
    required this.assetClassLabel,
    required this.pct,
    required this.monthlyAmount,
    this.name,
    this.dividendYieldPct,
    this.dividendPerShare,
  });

  final String ticker;
  final String kind;
  final String assetClassLabel;
  final int pct;
  final int monthlyAmount;
  final String? name;
  final double? dividendYieldPct;
  final double? dividendPerShare;
}

/// Lo que la card necesita del resultado de la tool.
class BuyPlanCardData {
  const BuyPlanCardData({
    required this.monthlyAmount,
    required this.items,
    required this.realYield,
    required this.assumedYieldPct,
    required this.targetBefore,
    required this.targetAfter,
    required this.monthlyBefore,
    required this.monthlyAfter,
    required this.annualDividends,
    this.weightedYieldPct,
    this.desiredMonthlyIncome,
  });

  final int monthlyAmount;
  final List<BuyPlanItem> items;
  final bool realYield;
  final double? weightedYieldPct;
  final double assumedYieldPct;
  final int targetBefore;
  final int targetAfter;
  final int monthlyBefore;
  final int monthlyAfter;
  final int annualDividends;
  final double? desiredMonthlyIncome;

  /// Todo número de la compra: lo único que Porty puede citar en el texto.
  Iterable<double> get backingNumbers sync* {
    final raw = <double>[
      monthlyAmount.toDouble(),
      targetBefore.toDouble(),
      targetAfter.toDouble(),
      monthlyBefore.toDouble(),
      monthlyAfter.toDouble(),
      annualDividends.toDouble(),
      annualDividends / 12,
      if (desiredMonthlyIncome != null) desiredMonthlyIncome!,
      for (final i in items) ...[
        i.monthlyAmount.toDouble(),
        if (i.dividendPerShare != null) i.dividendPerShare!,
      ],
    ];
    for (final v in raw) {
      yield v;
      yield v / 1e3;
      yield v / 1e6;
    }
    for (final i in items) {
      yield i.pct.toDouble();
      if (i.dividendYieldPct != null) yield i.dividendYieldPct!;
    }
    if (weightedYieldPct != null) yield weightedYieldPct!;
    yield assumedYieldPct;
    yield BuyPlanBuilder.maxStockShare * 100;
  }

  /// La compra [buyPlanId] entre [calls], o `null`.
  static BuyPlanCardData? from(List<ToolCallRecord> calls, String buyPlanId) {
    if (buyPlanId.isEmpty) return null;
    for (final call in calls.reversed) {
      if (call.name != GetMonthlyBuyPlanTool.toolName) continue;
      if (call.status != 'ok') continue;
      if (call.result[BuyPlanBuilder.buyPlanIdKey] != buyPlanId) continue;
      return fromToolResult(call.result);
    }
    return null;
  }

  static BuyPlanCardData? fromToolResult(Map<String, Object?> r) {
    final rawItems = r['items'];
    if (rawItems is! List || rawItems.isEmpty) return null;
    double? d(Object? v) => v is num ? v.toDouble() : null;
    int i(Object? v) => v is num ? v.round() : 0;
    final before = r['plan_before'] as Map? ?? const {};
    final after = r['plan_after'] as Map? ?? const {};
    final plan = r['plan'] as Map? ?? const {};
    final income = plan['income'] as Map? ?? const {};
    return BuyPlanCardData(
      monthlyAmount: i(r['monthly_amount']),
      items: [
        for (final it in rawItems.whereType<Map>())
          BuyPlanItem(
            ticker: '${it['ticker']}',
            kind: '${it['kind'] ?? DividendFetcher.kindOther}',
            assetClassLabel: '${it['asset_class_label'] ?? ''}',
            pct: i(it['pct']),
            monthlyAmount: i(it['monthly_amount']),
            name: it['name'] as String?,
            dividendYieldPct: d(it['dividend_yield_pct']),
            dividendPerShare: d(it['dividend_per_share_annual']),
          ),
      ],
      realYield: r['yield_source'] == 'real',
      weightedYieldPct: d(r['weighted_dividend_yield_pct']),
      assumedYieldPct: d(r['assumed_dividend_yield_pct']) ?? 3.5,
      targetBefore: i(before['target_amount']),
      targetAfter: i(after['target_amount']),
      monthlyBefore: i(before['required_monthly_savings']),
      monthlyAfter: i(after['required_monthly_savings']),
      annualDividends: i(after['annual_dividends_at_target']),
      desiredMonthlyIncome: d(income['desired_monthly_income']),
    );
  }
}

class QaBuyPlanCard extends StatelessWidget {
  const QaBuyPlanCard({super.key, required this.data});

  final BuyPlanCardData data;

  @override
  Widget build(BuildContext context) {
    final items = data.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        QaCardTitle(
          title: 'Tu compra mensual',
          subtitle: 'Lo que comprarías cada mes',
          icon: Icons.shopping_basket_outlined,
        ),
        const SizedBox(height: QaSpace.sectionGap),
        const QaSectionLabel('Cada mes invertís'),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(QaFormat.money(data.monthlyAmount), style: QaText.display),
            const SizedBox(width: 4),
            Text('/ mes', style: QaText.label),
          ],
        ),
        const SizedBox(height: QaSpace.gap),
        QaSegmentedBar(
          segments: [
            for (var k = 0; k < items.length; k++)
              QaSegment(
                value: items[k].pct.toDouble(),
                color: QaPalette.series(k),
              ),
          ],
        ),
        const SizedBox(height: QaSpace.sectionGap),
        for (var k = 0; k < items.length; k++) ...[
          if (k > 0) const SizedBox(height: QaSpace.rowGap),
          _ItemRow(item: items[k], color: QaPalette.series(k)),
        ],
        QaSection(title: 'Con estos rendimientos', child: _impact()),
        QaSection(
          child: Text(
            'Es un ejemplo para simular, no una recomendación de compra. '
            'Los dividendos no están garantizados y los rendimientos cambian '
            'con el precio. Tope de '
            '${(BuyPlanBuilder.maxStockShare * 100).round()}% por acción '
            'individual; la base son ETFs diversificados.',
            style: QaText.caption,
          ),
        ),
        const QaFollowUpBar(
          items: [
            QaFollowUp(
              'Ver plan actualizado',
              'Mostrame el plan con estos rendimientos',
              icon: Icons.show_chart_rounded,
            ),
            QaFollowUp(
              'Otros instrumentos',
              'Armá la compra mensual con otros instrumentos',
              icon: Icons.swap_horiz_rounded,
            ),
            QaFollowUp(
              'Cuánto paga cada uno',
              '¿Cuánto paga de dividendos cada uno?',
              icon: Icons.payments_outlined,
            ),
          ],
        ),
      ],
    );
  }

  Widget _impact() {
    final yieldLine =
        data.realYield && data.weightedYieldPct != null
            ? 'Rinden en promedio ${_pct(data.weightedYieldPct!)} por año en '
                'dividendos (el plan suponía ${_pct(data.assumedYieldPct)}).'
            : 'No hay datos de dividendos suficientes de estos instrumentos: '
                'el plan sigue con el supuesto de '
                '${_pct(data.assumedYieldPct)}.';
    final desired = data.desiredMonthlyIncome;
    final changed = data.targetAfter != data.targetBefore;
    final stats = <QaStat>[
      QaStat(
        label:
            changed
                ? 'Meta (antes ${QaFormat.money(data.targetBefore)})'
                : 'Meta',
        value: QaFormat.money(data.targetAfter),
      ),
      QaStat(
        label:
            desired != null
                ? 'Cobrarías por mes'
                : 'Dividendos por mes al llegar',
        value: QaFormat.money(desired ?? data.annualDividends / 12),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(yieldLine, style: QaText.body),
        const SizedBox(height: QaSpace.gap),
        QaInset(child: QaStatGrid(stats: stats)),
      ],
    );
  }

  static String _pct(double v) =>
      '${v.toStringAsFixed(1).replaceAll('.', ',')}%';
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.color});

  final BuyPlanItem item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final kind = switch (item.kind) {
      DividendFetcher.kindEtf => 'ETF',
      DividendFetcher.kindStock => 'Acción',
      _ => null,
    };
    final yieldText =
        item.dividendYieldPct == null
            ? 'sin dato de dividendo'
            : item.dividendYieldPct! <= 0
            ? 'no paga dividendos'
            : 'rinde ${item.dividendYieldPct!.toStringAsFixed(1).replaceAll('.', ',')}%';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        QaTickerAvatar(ticker: item.ticker, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      item.ticker,
                      style: QaText.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (kind != null) ...[const SizedBox(width: 6), QaTag(kind)],
                  const Spacer(),
                  Text(
                    '${QaFormat.money(item.monthlyAmount)}/mes',
                    style: QaText.value,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        if (item.name != null) item.name!,
                        if (item.assetClassLabel.isNotEmpty)
                          item.assetClassLabel,
                      ].join(' · '),
                      style: QaText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${item.pct}% · $yieldText', style: QaText.caption),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
