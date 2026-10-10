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
  static List<PortfolioHistoryPoint> _strictFilterByDuration(
    List<PortfolioHistoryPoint> points,
    Duration duration,
  ) {
    if (points.isEmpty) return points;

    final end = points.last.date;
    final start = end.subtract(duration);
    return points.where((p) => !p.date.isBefore(start)).toList();
  }

  /// Filtro "permisivo": si no hay suficiente historial dentro de la
  /// ventana pedida, devuelve el historial completo en vez de una lista
  /// corta — pensado para el chart de Home, donde mostrar todo el rango
  /// disponible es mejor UX que un gráfico vacío.
  static List<PortfolioHistoryPoint> filterByDuration(
    List<PortfolioHistoryPoint> points,
    Duration duration,
  ) {
    final filtered = _strictFilterByDuration(points, duration);
    return filtered.length >= 2 ? filtered : points;
  }

  /// Indica si hay al menos dos puntos *dentro* de la ventana exacta del
  /// período (sin el fallback permisivo de [filterByDuration]). Úsalo
  /// cuando el resultado se va a nombrar como "último día/semana/...":
  /// el fallback permisivo alcanza siempre >=2 puntos con el historial
  /// completo, así que reusarlo acá enmascara los casos sin granularidad
  /// real para ese período.
  static bool hasSufficientHistory(
    List<PortfolioHistoryPoint> points,
    Duration duration,
  ) {
    return _strictFilterByDuration(points, duration).length >= 2;
  }

  /// Retorno del período comparando P&L no realizado al inicio vs fin.
  static PeriodPnl periodPnlFromHistory(List<PortfolioHistoryPoint> points) {
    if (points.isEmpty) return PeriodPnl.empty;

    if (points.length == 1) {
      final point = points.first;
      final absolute = point.unrealizedPnl;
      final percent =
          point.totalCostBasis > 0
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
    final percent =
        start.totalCostBasis > 0
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
    final filtered = _strictFilterByDuration(history, duration);
    if (filtered.length < 2) return PeriodPnl.empty;
    return periodPnlFromHistory(filtered);
  }
}
