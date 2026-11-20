import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_period_utils.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_series_builder.dart';

/// De cuándo es la variación: del día de hoy o del último día con datos.
enum DayMovePeriod {
  today,
  lastClose;

  String get wire => switch (this) {
    DayMovePeriod.today => 'today',
    DayMovePeriod.lastClose => 'last_close',
  };
}

/// El ticker que más aportó (o restó) a la variación del día.
class TopContributor {
  const TopContributor({required this.ticker, required this.amount});

  /// Símbolo normalizado (mayúsculas).
  final String ticker;

  /// `cantidad × (cierre último − cierre anterior)`, en dólares.
  final double amount;
}

/// La variación del último día del historial: lo que muestran la línea
/// "Hoy" de la Home y el widget de la pantalla de inicio. Misma cuenta que
/// el gráfico (la plata nueva no cuenta como ganancia).
class PortfolioDayMove {
  const PortfolioDayMove({
    required this.absolute,
    required this.percent,
    required this.period,
    required this.asOfDay,
    required this.topContributor,
  });

  /// Variación en dólares entre los dos últimos puntos del historial.
  final double absolute;

  /// Variación en % sobre el capital invertido (Dietz simple).
  final double percent;
  final DayMovePeriod period;

  /// Día del último punto del historial; `null` sin historial.
  final DateTime? asOfDay;

  /// `null` si falta algún dato, si hay empate o si no hubo movimiento.
  final TopContributor? topContributor;

  /// Con menos de dos puntos no hay variación que medir: queda en 0 (una
  /// cartera cargada hoy no ganó nada hoy). Sin historial, `lastClose`.
  ///
  /// [positions] y [candlesByTicker] (por `position.ticker` tal cual) solo
  /// hacen falta para [topContributor]. [now] es para tests.
  static PortfolioDayMove compute({
    required List<PortfolioHistoryPoint> history,
    List<Position> positions = const [],
    Map<String, List<PriceCandle>> candlesByTicker = const {},
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    if (history.isEmpty) {
      return const PortfolioDayMove(
        absolute: 0,
        percent: 0,
        period: DayMovePeriod.lastClose,
        asOfDay: null,
        topContributor: null,
      );
    }
    final last = history.last;
    final isToday =
        last.date.year == today.year &&
        last.date.month == today.month &&
        last.date.day == today.day;
    final period = isToday ? DayMovePeriod.today : DayMovePeriod.lastClose;
    if (history.length < 2) {
      return PortfolioDayMove(
        absolute: 0,
        percent: 0,
        period: period,
        asOfDay: last.date,
        topContributor: null,
      );
    }
    final previous = history[history.length - 2];
    final pnl = PortfolioPeriodUtils.periodPnlFromHistory([previous, last]);
    return PortfolioDayMove(
      absolute: pnl.absolute,
      percent: pnl.percent,
      period: period,
      asOfDay: last.date,
      topContributor: _topContributor(
        positions: positions,
        candlesByTicker: candlesByTicker,
        previousDay: previous.date,
        lastDay: last.date,
        up: pnl.absolute >= 0,
        moved: pnl.absolute != 0,
      ),
    );
  }

  static TopContributor? _topContributor({
    required List<Position> positions,
    required Map<String, List<PriceCandle>> candlesByTicker,
    required DateTime previousDay,
    required DateTime lastDay,
    required bool up,
    required bool moved,
  }) {
    if (!moved || positions.isEmpty) return null;
    final byTicker = <String, double>{};
    for (final p in positions) {
      // Comprada después del día anterior: la plata nueva no es ganancia.
      if (p.purchaseDateKnown && p.purchaseDate.isAfter(previousDay)) continue;
      final candles = candlesByTicker[p.ticker];
      if (candles == null) return null;
      final close = PortfolioSeriesBuilder.closeOnOrBefore(candles, lastDay);
      final before = PortfolioSeriesBuilder.closeOnOrBefore(
        candles,
        previousDay,
      );
      if (close == null || before == null) return null;
      final key = PortfolioCalculator.normalizeTicker(p.ticker);
      byTicker[key] = (byTicker[key] ?? 0) + p.quantity * (close - before);
    }
    if (byTicker.isEmpty) return null;
    final sorted =
        byTicker.entries.toList()..sort(
          (a, b) =>
              up ? b.value.compareTo(a.value) : a.value.compareTo(b.value),
        );
    final best = sorted.first;
    // Tiene que ir en la dirección del movimiento y sin empate.
    if (up ? best.value <= 0 : best.value >= 0) return null;
    if (sorted.length > 1 && (sorted[1].value - best.value).abs() < 1e-9) {
      return null;
    }
    return TopContributor(ticker: best.key, amount: best.value);
  }
}
