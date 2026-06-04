import 'dart:convert';

import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';

/// Serializa el portfolio actual para el contexto del asistente.
abstract final class PortfolioContextBuilder {
  static String buildJson(PortfolioSummary? summary, {DateTime? asOf}) {
    final timestamp = (asOf ?? DateTime.now()).toUtc().toIso8601String();

    if (summary == null || summary.valuations.isEmpty) {
      return jsonEncode({
        'as_of': timestamp,
        'has_positions': false,
        'total_value': 0,
        'total_pnl_abs': 0,
        'total_pnl_pct': 0,
        'positions': <Map<String, Object?>>[],
      });
    }

    final total = summary.totalValue;
    final positions = <Map<String, Object?>>[];
    for (final v in summary.valuations) {
      final weightPct = total > 0 ? (v.marketValue / total) * 100 : 0.0;
      positions.add({
        'ticker': v.position.ticker,
        'shares': v.position.quantity,
        'current_price': v.currentPrice,
        'market_value': v.marketValue,
        'pnl_abs': v.pnlAbsolute,
        'pnl_pct': v.pnlPercent,
        'weight_pct': double.parse(weightPct.toStringAsFixed(2)),
      });
    }

    return jsonEncode({
      'as_of': timestamp,
      'has_positions': true,
      'total_value': summary.totalValue,
      'total_cost_basis': summary.totalCostBasis,
      'total_pnl_abs': summary.totalPnlAbsolute,
      'total_pnl_pct': summary.totalPnlPercent,
      'positions': positions,
    });
  }
}
