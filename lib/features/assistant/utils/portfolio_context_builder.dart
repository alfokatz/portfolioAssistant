import 'dart:convert';

import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_period_utils.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/sector_concentration_checker.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/sector_display_name.dart';

/// Serializa el portfolio actual para el contexto del asistente.
abstract final class PortfolioContextBuilder {
  static String buildJson(
    PortfolioSummary? summary, {
    List<PortfolioHistoryPoint> history = const [],
    Map<String, Map<String, Object?>> positionPeriods = const {},
    List<ClosedPosition> closedPositions = const [],
    Map<String, String> sectorByTicker = const {},
    SectorConcentration? sectorConcentration,
    DateTime? asOf,
  }) {
    final timestamp = (asOf ?? DateTime.now()).toUtc().toIso8601String();
    final hasOpen = summary != null && summary.valuations.isNotEmpty;
    final hasClosed = closedPositions.isNotEmpty;
    final closedMaps = _serializeClosedPositions(closedPositions);
    final closedTotals = _closedTotals(closedPositions);

    if (!hasOpen && !hasClosed) {
      return jsonEncode(_buildEmptyPayload(timestamp));
    }

    final openSummary = hasOpen ? summary : null;
    final openPositions = <Map<String, Object?>>[];
    if (openSummary != null) {
      final total = openSummary.totalValue;
      for (final v in openSummary.valuations) {
        final weightPct = total > 0 ? (v.marketValue / total) * 100 : 0.0;
        openPositions.add({
          'ticker': v.position.ticker,
          'shares': v.position.quantity,
          'current_price': v.currentPrice,
          'market_value': v.marketValue,
          'pnl_abs': v.pnlAbsolute,
          'pnl_pct': v.pnlPercent,
          'weight_pct': double.parse(weightPct.toStringAsFixed(2)),
          'sector': sectorByTicker[v.position.ticker.toUpperCase()] ??
              SectorDisplayName.unclassified,
        });
      }
    }

    final concentration = sectorConcentration ??
        (hasOpen
            ? SectorConcentrationChecker.fromSummary(
                openSummary,
                sectorByTicker: sectorByTicker,
              )
            : const SectorConcentration(sectorWeights: {}));

    final payload = <String, Object?>{
      'as_of': timestamp,
      'has_positions': hasOpen,
      'has_closed_positions': hasClosed,
      'has_portfolio_data': hasOpen || hasClosed,
      'total_value': openSummary?.totalValue ?? 0,
      'total_cost_basis': openSummary?.totalCostBasis ?? 0,
      'total_pnl_abs': openSummary?.totalPnlAbsolute ?? 0,
      'total_pnl_pct': openSummary?.totalPnlPercent ?? 0,
      'pnl_scope': hasOpen
          ? 'all_time_unrealized — ganancia/pérdida desde la compra en posiciones ABIERTAS, NO es un período'
          : 'sin posiciones abiertas — total_pnl_* no aplica',
      'period_returns': hasOpen ? _buildPeriodReturns(history) : <String, Object?>{},
      'position_periods': hasOpen ? positionPeriods : <String, Object?>{},
      'positions': openPositions,
      'closed_positions': closedMaps,
      'closed_pnl_total_abs': closedTotals.abs,
      'closed_pnl_total_cost_basis': closedTotals.costBasis,
      'closed_pnl_total_pct': closedTotals.percent,
      'sector_concentration': concentration.sectorWeights,
      'concentration_warning': concentration.overweightSector != null,
    };

    if (concentration.overweightSector != null) {
      payload['overweight_sector'] = concentration.overweightSector;
    }

    return jsonEncode(payload);
  }

  static Map<String, Object?> _buildEmptyPayload(String timestamp) {
    return {
      'as_of': timestamp,
      'has_positions': false,
      'has_closed_positions': false,
      'has_portfolio_data': false,
      'total_value': 0,
      'total_pnl_abs': 0,
      'total_pnl_pct': 0,
      'pnl_scope': 'all_time_unrealized',
      'period_returns': <String, Object?>{},
      'position_periods': <String, Object?>{},
      'positions': <Map<String, Object?>>[],
      'closed_positions': <Map<String, Object?>>[],
      'closed_pnl_total_abs': 0,
      'closed_pnl_total_cost_basis': 0,
      'sector_concentration': <String, double>{},
      'concentration_warning': false,
    };
  }

  static List<Map<String, Object?>> _serializeClosedPositions(
    List<ClosedPosition> positions,
  ) {
    return [
      for (final p in positions)
        {
          'ticker': p.ticker,
          'quantity': p.quantity,
          'avg_purchase_price': _round2(p.avgPurchasePrice),
          'close_price': _round2(p.closePrice),
          'cost_basis': _round2(p.costBasis),
          'proceeds': _round2(p.proceeds),
          'pnl_abs': _round2(p.pnlAbsolute),
          'pnl_pct': _round2(p.pnlPercent),
          'close_date': p.closeDate.toUtc().toIso8601String(),
          'closed_at': p.closedAt.toUtc().toIso8601String(),
        },
    ];
  }

  static ({double abs, double costBasis, double percent}) _closedTotals(
    List<ClosedPosition> positions,
  ) {
    if (positions.isEmpty) {
      return (abs: 0, costBasis: 0, percent: 0);
    }

    final costBasis = positions.fold<double>(0, (sum, p) => sum + p.costBasis);
    final abs = positions.fold<double>(0, (sum, p) => sum + p.pnlAbsolute);
    final percent = costBasis > 0 ? (abs / costBasis) * 100 : 0.0;

    return (
      abs: _round2(abs),
      costBasis: _round2(costBasis),
      percent: _round2(percent),
    );
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
