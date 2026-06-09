import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';

/// Rendimiento del portfolio en un intervalo de tiempo.
class PeriodPnl {
  final double absolute;
  final double percent;
  final double valueStart;
  final double valueEnd;

  const PeriodPnl({
    required this.absolute,
    required this.percent,
    this.valueStart = 0,
    this.valueEnd = 0,
  });

  static const empty = PeriodPnl(absolute: 0, percent: 0);
}

/// Cálculo de retornos por período a partir del historial diario.
abstract final class PortfolioPeriodUtils {
  static List<PortfolioHistoryPoint> filterByDuration(
    List<PortfolioHistoryPoint> points,
    Duration duration,
  ) {
    if (points.isEmpty) return points;

    final end = points.last.date;
    final start = end.subtract(duration);
    final filtered = points.where((p) => !p.date.isBefore(start)).toList();
    return filtered.length >= 2 ? filtered : points;
  }

  /// Retorno del período comparando P&L no realizado al inicio vs fin.
  static PeriodPnl periodPnlFromHistory(List<PortfolioHistoryPoint> points) {
    if (points.isEmpty) return PeriodPnl.empty;

    if (points.length == 1) {
      final point = points.first;
      final absolute = point.unrealizedPnl;
      final percent = point.totalCostBasis > 0
          ? (absolute / point.totalCostBasis) * 100
          : 0.0;
      return PeriodPnl(
        absolute: absolute,
        percent: percent,
        valueStart: point.totalValue,
        valueEnd: point.totalValue,
      );
    }

    final start = points.first;
    final end = points.last;
    final absolute = end.unrealizedPnl - start.unrealizedPnl;
    final percent = start.totalCostBasis > 0
        ? (absolute / start.totalCostBasis) * 100
        : 0.0;
    return PeriodPnl(
      absolute: absolute,
      percent: percent,
      valueStart: start.totalValue,
      valueEnd: end.totalValue,
    );
  }

  static PeriodPnl forDuration({
    required List<PortfolioHistoryPoint> history,
    required Duration duration,
  }) {
    if (history.length < 2) return PeriodPnl.empty;
    final filtered = filterByDuration(history, duration);
    if (filtered.length < 2) return PeriodPnl.empty;
    return periodPnlFromHistory(filtered);
  }
}
