import 'dart:convert';

import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_period_utils.dart';

/// Serializa el portfolio actual para el contexto del asistente.
abstract final class PortfolioContextBuilder {
  static String buildJson(
    PortfolioSummary? summary, {
    List<PortfolioHistoryPoint> history = const [],
    Map<String, Map<String, Object?>> positionPeriods = const {},
    DateTime? asOf,
  }) {
    final timestamp = (asOf ?? DateTime.now()).toUtc().toIso8601String();

    if (summary == null || summary.valuations.isEmpty) {
      return jsonEncode({
        'as_of': timestamp,
        'has_positions': false,
        'total_value': 0,
        'total_pnl_abs': 0,
        'total_pnl_pct': 0,
        'pnl_scope': 'all_time_unrealized',
        'period_returns': <String, Object?>{},
        'position_periods': <String, Object?>{},
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
      'pnl_scope':
          'all_time_unrealized — ganancia/pérdida desde la compra, NO es un período',
      'period_returns': _buildPeriodReturns(history),
      'position_periods': positionPeriods,
      'positions': positions,
    });
  }

  static Map<String, Object?> _buildPeriodReturns(
    List<PortfolioHistoryPoint> history,
  ) {
    const periods = <String, ({String labelEs, Duration duration})>{
      'day': (labelEs: 'último día', duration: Duration(days: 1)),
      'week': (labelEs: 'últimos 7 días', duration: Duration(days: 7)),
      'month': (labelEs: 'últimos 30 días', duration: Duration(days: 30)),
      'quarter': (labelEs: 'últimos 90 días', duration: Duration(days: 90)),
      'year': (labelEs: 'último año', duration: Duration(days: 365)),
    };

    final result = <String, Object?>{};
    for (final entry in periods.entries) {
      final pnl = PortfolioPeriodUtils.forDuration(
        history: history,
        duration: entry.value.duration,
      );
      final filtered = PortfolioPeriodUtils.filterByDuration(
        history,
        entry.value.duration,
      );
      result[entry.key] = {
        'label_es': entry.value.labelEs,
        'pnl_abs': _round2(pnl.absolute),
        'pnl_pct': _round2(pnl.percent),
        'value_start': _round2(pnl.valueStart),
        'value_end': _round2(pnl.valueEnd),
        'has_sufficient_history': filtered.length >= 2,
      };
    }

    return result;
  }

  static double _round2(double value) =>
      double.parse(value.toStringAsFixed(2));
}
