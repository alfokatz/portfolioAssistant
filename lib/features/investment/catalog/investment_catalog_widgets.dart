import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:intl/intl.dart';
import 'package:portfolio_assistant/features/analysis/catalog/analysis_colors.dart';
import 'package:portfolio_assistant/shared/utils/genui_helpers.dart';

abstract final class InvestmentCatalogWidgets {
  static Widget investmentOpportunityCard(CatalogItemContext ctx) {
    final data = _OpportunityData.fromMap(ctx.data as JsonMap);
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final riskStyle = _riskStyle(data.riskLevel);

    return Card(
      color: AnalysisColors.cardBackground,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.ticker,
                        style: const TextStyle(
                          color: AnalysisColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        data.companyName,
                        style: const TextStyle(
                          color: AnalysisColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: riskStyle.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    riskStyle.label,
                    style: TextStyle(
                      color: riskStyle.color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              currency.format(data.currentPrice),
              style: const TextStyle(
                color: AnalysisColors.textSecondary,
                fontSize: 13,
              ),
            ),
            Text(
              data.sector,
              style: const TextStyle(
                color: AnalysisColors.textSecondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AnalysisColors.profit.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Retorno esperado: ${data.expectedReturn}',
                style: const TextStyle(
                  color: AnalysisColors.profit,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 10),
            ...data.pros.take(3).map(
                  (p) => _bulletRow(
                    icon: Icons.add_circle_outline,
                    text: p,
                    color: AnalysisColors.profit,
                  ),
                ),
            ...data.cons.take(3).map(
                  (c) => _bulletRow(
                    icon: Icons.remove_circle_outline,
                    text: c,
                    color: AnalysisColors.loss,
                  ),
                ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  'Fit',
                  style: TextStyle(
                    color: AnalysisColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (data.fitScore.clamp(0, 100)) / 100,
                      minHeight: 8,
                      backgroundColor: AnalysisColors.textSecondary.withValues(
                        alpha: 0.2,
                      ),
                      color: AnalysisColors.profit,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${data.fitScore.round()}',
                  style: const TextStyle(
                    color: AnalysisColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget riskProfileSlider(CatalogItemContext ctx) {
    final data = _RiskSliderData.fromMap(ctx.data as JsonMap);
    final path = data.path.isNotEmpty ? data.path : '/user/risk_profile';

    return BoundNumber(
      dataContext: ctx.dataContext,
      value: {'path': path},
      builder: (context, value) {
        final current = (value?.toDouble() ?? data.currentValue).clamp(0.0, 100.0);

        return Card(
          color: AnalysisColors.cardBackground,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  style: const TextStyle(
                    color: AnalysisColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Slider(
                  value: current,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: current.round().toString(),
                  onChanged: (v) {
                    ctx.dataContext.update(DataPath(path), v);
                  },
                  onChangeEnd: (v) {
                    ctx.dispatchEvent(
                      UserActionEvent(
                        name: 'risk_profile_updated',
                        sourceComponentId: ctx.id,
                        context: {'value': v},
                      ),
                    );
                  },
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Conservador',
                      style: TextStyle(
                        color: AnalysisColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      'Agresivo',
                      style: TextStyle(
                        color: AnalysisColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget budgetAllocationCard(CatalogItemContext ctx) {
    final data = _BudgetData.fromMap(ctx.data as JsonMap);
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Card(
      color: AnalysisColors.cardBackground,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Presupuesto: ${currency.format(data.totalBudget)}',
              style: const TextStyle(
                color: AnalysisColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            ...data.allocations.map((a) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          a.ticker,
                          style: const TextStyle(
                            color: AnalysisColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          currency.format(a.amount),
                          style: const TextStyle(
                            color: AnalysisColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (a.percent.clamp(0, 100)) / 100,
                        minHeight: 6,
                        backgroundColor:
                            AnalysisColors.textSecondary.withValues(alpha: 0.2),
                        color: AnalysisColors.info,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      a.rationale,
                      style: const TextStyle(
                        color: AnalysisColors.textSecondary,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  static Widget marketContextCard(CatalogItemContext ctx) {
    final data = _MarketContextData.fromMap(ctx.data as JsonMap);
    final icon = _sentimentIcon(data.sentiment);

    return Card(
      color: AnalysisColors.cardBackground,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AnalysisColors.info, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    style: const TextStyle(
                      color: AnalysisColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    data.summary,
                    style: const TextStyle(
                      color: AnalysisColors.textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    data.relevance,
                    style: const TextStyle(
                      color: AnalysisColors.textSecondary,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget investmentConfirmCard(CatalogItemContext ctx) {
    final data = _ConfirmData.fromMap(ctx.data as JsonMap);
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final eventName = data.confirmEvent.isNotEmpty
        ? data.confirmEvent
        : 'investment_confirmed';

    return Card(
      color: AnalysisColors.cardBackground,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Confirmar inversión',
              style: TextStyle(
                color: AnalysisColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            _confirmRow('Activo', data.ticker),
            _confirmRow('Acciones', data.shares.toStringAsFixed(2)),
            _confirmRow('Precio', currency.format(data.pricePerShare)),
            _confirmRow('Total', currency.format(data.totalAmount)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ctx.dispatchEvent(
                UserActionEvent(
                  name: eventName,
                  sourceComponentId: ctx.id,
                  context: {
                    'ticker': data.ticker,
                    'shares': data.shares,
                    'pricePerShare': data.pricePerShare,
                    'totalAmount': data.totalAmount,
                  },
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AnalysisColors.profit,
                foregroundColor: AnalysisColors.textPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Confirmar inversión'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => ctx.dispatchEvent(
                UserActionEvent(
                  name: 'investment_cancelled',
                  sourceComponentId: ctx.id,
                  context: const {},
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AnalysisColors.textSecondary,
                side: const BorderSide(color: AnalysisColors.textSecondary),
              ),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _bulletRow({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _confirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AnalysisColors.textSecondary)),
          Text(
            value,
            style: const TextStyle(
              color: AnalysisColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static _RiskStyle _riskStyle(String level) => switch (level) {
        'low' => _RiskStyle('Bajo', AnalysisColors.profit),
        'high' => _RiskStyle('Alto', AnalysisColors.loss),
        _ => _RiskStyle('Moderado', AnalysisColors.warning),
      };

  static IconData _sentimentIcon(String sentiment) => switch (sentiment) {
        'bullish' => Icons.trending_up,
        'bearish' => Icons.trending_down,
        _ => Icons.trending_flat,
      };
}

class _RiskStyle {
  final String label;
  final Color color;
  const _RiskStyle(this.label, this.color);
}

extension type _OpportunityData.fromMap(JsonMap _json) {
  String get ticker =>
      GenUiHelpers.safeString(_json['ticker'], defaultValue: '—');
  String get companyName =>
      GenUiHelpers.safeString(_json['companyName'], defaultValue: '');
  double get currentPrice =>
      GenUiHelpers.safeDouble(_json['currentPrice'], defaultValue: 0);
  String get sector =>
      GenUiHelpers.safeString(_json['sector'], defaultValue: '');
  String get riskLevel => GenUiHelpers.safeEnum(
        _json['riskLevel'],
        ['low', 'moderate', 'high'],
        defaultValue: 'moderate',
      );
  String get expectedReturn =>
      GenUiHelpers.safeString(_json['expectedReturn'], defaultValue: '');
  List<String> get pros =>
      GenUiHelpers.safeStringList(_json['pros']);
  List<String> get cons =>
      GenUiHelpers.safeStringList(_json['cons']);
  double get fitScore =>
      GenUiHelpers.safeDouble(_json['fitScore'], defaultValue: 0);
}

extension type _RiskSliderData.fromMap(JsonMap _json) {
  double get currentValue =>
      GenUiHelpers.safeDouble(_json['currentValue'], defaultValue: 50);
  String get label => GenUiHelpers.safeString(
        _json['label'],
        defaultValue: 'Conservador → Agresivo',
      );
  String get path => GenUiHelpers.safeString(
        _json['path'],
        defaultValue: '/user/risk_profile',
      );
}

extension type _AllocationItem.fromMap(JsonMap _json) {
  String get ticker =>
      GenUiHelpers.safeString(_json['ticker'], defaultValue: '—');
  double get amount =>
      GenUiHelpers.safeDouble(_json['amount'], defaultValue: 0);
  double get percent =>
      GenUiHelpers.safeDouble(_json['percent'], defaultValue: 0);
  String get rationale =>
      GenUiHelpers.safeString(_json['rationale'], defaultValue: '');
}

extension type _BudgetData.fromMap(JsonMap _json) {
  double get totalBudget =>
      GenUiHelpers.safeDouble(_json['totalBudget'], defaultValue: 0);
  List<_AllocationItem> get allocations {
    final list = _json['allocations'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => _AllocationItem.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }
}

extension type _MarketContextData.fromMap(JsonMap _json) {
  String get title =>
      GenUiHelpers.safeString(_json['title'], defaultValue: '');
  String get summary =>
      GenUiHelpers.safeString(_json['summary'], defaultValue: '');
  String get sentiment => GenUiHelpers.safeEnum(
        _json['sentiment'],
        ['bullish', 'bearish', 'neutral'],
        defaultValue: 'neutral',
      );
  String get relevance =>
      GenUiHelpers.safeString(_json['relevance'], defaultValue: '');
}

extension type _ConfirmData.fromMap(JsonMap _json) {
  String get ticker =>
      GenUiHelpers.safeString(_json['ticker'], defaultValue: '—');
  double get shares =>
      GenUiHelpers.safeDouble(_json['shares'], defaultValue: 0);
  double get pricePerShare =>
      GenUiHelpers.safeDouble(_json['pricePerShare'], defaultValue: 0);
  double get totalAmount =>
      GenUiHelpers.safeDouble(_json['totalAmount'], defaultValue: 0);
  String get confirmEvent => GenUiHelpers.safeString(
        _json['confirmEvent'],
        defaultValue: 'investment_confirmed',
      );
}
