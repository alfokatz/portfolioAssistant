import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_series_builder.dart';

/// Una posición que movió la cartera en el último cierre.
class BriefMover {
  const BriefMover({
    required this.ticker,
    required this.pct,
    required this.contributionAbs,
    required this.weightPct,
  });

  /// Símbolo normalizado (mayúsculas).
  final String ticker;

  /// Variación del activo entre los dos últimos cierres, en %.
  final double pct;

  /// `cantidad × (cierre último − cierre anterior)`, en dólares: lo que
  /// aportó (o restó) a la cartera.
  final double contributionAbs;

  /// Peso en la cartera al último cierre, en %.
  final double weightPct;

  Map<String, Object?> toJson() => {
    'ticker': ticker,
    'pct': pct,
    'contribution_abs': contributionAbs,
    'weight_pct': weightPct,
  };

  static BriefMover? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final ticker = raw['ticker'];
    final pct = raw['pct'];
    final contribution = raw['contribution_abs'];
    final weight = raw['weight_pct'];
    if (ticker is! String || ticker.isEmpty) return null;
    if (pct is! num || contribution is! num || weight is! num) return null;
    return BriefMover(
      ticker: ticker,
      pct: pct.toDouble(),
      contributionAbs: contribution.toDouble(),
      weightPct: weight.toDouble(),
    );
  }
}

/// Los números del brief (§3.4 `payload.numbers`): sin IA, de la cuenta de
/// la Home. `abs`, `pct`, `period` y `asOfDay` salen de [PortfolioDayMove]
/// (la línea 1D de la Home y el widget): nunca se recalculan por otro camino.
class DailyBriefNumbers {
  const DailyBriefNumbers({
    required this.period,
    required this.asOfDay,
    required this.abs,
    required this.pct,
    required this.movers,
  });

  /// Sin historial: no hay brief.
  static const empty = DailyBriefNumbers(
    period: DayMovePeriod.lastClose,
    asOfDay: null,
    abs: 0,
    pct: 0,
    movers: [],
  );

  final DayMovePeriod period;

  /// Día del último punto del historial (`null` sin historial).
  final DateTime? asOfDay;

  /// Variación en dólares del último cierre.
  final double abs;

  /// Variación en % del último cierre.
  final double pct;

  /// Las 2–3 posiciones que más aportaron en valor absoluto.
  final List<BriefMover> movers;

  bool get isEmpty => asOfDay == null;

  /// Cuántos movers se muestran como máximo.
  static const maxMovers = 3;

  /// [history] es el de la Home (`homeProvider.history`); [lots] sus
  /// compras; [candlesByTicker] las velas diarias por `position.ticker`
  /// tal cual. Un ticker sin velas queda fuera de los movers (nunca se
  /// inventa su aporte).
  static DailyBriefNumbers compute({
    required List<PortfolioHistoryPoint> history,
    required List<Position> lots,
    required Map<String, List<PriceCandle>> candlesByTicker,
    DateTime? now,
  }) {
    if (history.isEmpty) return empty;
    final move = PortfolioDayMove.compute(
      history: history,
      positions: lots,
      candlesByTicker: candlesByTicker,
      now: now,
    );
    return DailyBriefNumbers(
      period: move.period,
      asOfDay: move.asOfDay,
      abs: move.absolute,
      pct: move.percent,
      movers:
          history.length < 2
              ? const []
              : _movers(
                lots: lots,
                candles: candlesByTicker,
                previousDay: history[history.length - 2].date,
                lastDay: history.last.date,
              ),
    );
  }

  static List<BriefMover> _movers({
    required List<Position> lots,
    required Map<String, List<PriceCandle>> candles,
    required DateTime previousDay,
    required DateTime lastDay,
  }) {
    final contribution = <String, double>{};
    final value = <String, double>{};
    final before = <String, double>{};
    final after = <String, double>{};
    var total = 0.0;
    for (final p in lots) {
      final series = candles[p.ticker];
      if (series == null) continue;
      final key = PortfolioCalculator.normalizeTicker(p.ticker);
      final close = PortfolioSeriesBuilder.closeOnOrBefore(series, lastDay);
      if (close == null) continue;
      total += p.quantity * close;
      value[key] = (value[key] ?? 0) + p.quantity * close;
      // Comprada después del día anterior: la plata nueva no es ganancia
      // (igual que `PortfolioDayMove`).
      if (p.purchaseDateKnown && p.purchaseDate.isAfter(previousDay)) continue;
      final prev = PortfolioSeriesBuilder.closeOnOrBefore(series, previousDay);
      if (prev == null || prev == 0) continue;
      contribution[key] = (contribution[key] ?? 0) + p.quantity * (close - prev);
      before[key] = prev;
      after[key] = close;
    }
    if (total <= 0) return const [];
    final keys =
        contribution.keys.where((k) => contribution[k]!.abs() > 1e-9).toList()
          ..sort((a, b) {
            final byImpact = contribution[b]!.abs().compareTo(
              contribution[a]!.abs(),
            );
            return byImpact != 0 ? byImpact : a.compareTo(b);
          });
    return [
      for (final k in keys.take(maxMovers))
        BriefMover(
          ticker: k,
          pct: (after[k]! - before[k]!) / before[k]! * 100,
          contributionAbs: contribution[k]!,
          weightPct: (value[k] ?? 0) / total * 100,
        ),
    ];
  }

  Map<String, Object?> toJson() => {
    'period': period.wire,
    'as_of_day': asOfDay == null ? null : dayKey(asOfDay!),
    'abs': abs,
    'pct': pct,
    'movers': [for (final m in movers) m.toJson()],
  };

  static DailyBriefNumbers? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final abs = raw['abs'];
    final pct = raw['pct'];
    final asOf = DateTime.tryParse('${raw['as_of_day']}');
    if (abs is! num || pct is! num || asOf == null) return null;
    final movers = raw['movers'];
    return DailyBriefNumbers(
      period:
          raw['period'] == 'today'
              ? DayMovePeriod.today
              : DayMovePeriod.lastClose,
      asOfDay: DateTime(asOf.year, asOf.month, asOf.day),
      abs: abs.toDouble(),
      pct: pct.toDouble(),
      movers:
          movers is List
              ? movers.map(BriefMover.tryParse).whereType<BriefMover>().toList()
              : const [],
    );
  }

  /// `YYYY-MM-DD` de una fecha local.
  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
