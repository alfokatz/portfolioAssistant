import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/report_week.dart';

/// Cómo le fue a una posición (todas las compras de un ticker) en la semana.
class WeeklyPositionMove {
  const WeeklyPositionMove({
    required this.ticker,
    required this.valueStart,
    required this.valueEnd,
    required this.weightStart,
    required this.weightEnd,
    required this.contributionPp,
    required this.pricePct,
    required this.boughtThisWeek,
  });

  final String ticker;

  /// Valor al cierre del viernes anterior. Lo que se compró durante la
  /// semana entra a su precio de compra: plata nueva, no ganancia.
  final double valueStart;
  final double valueEnd;

  /// Peso en la cartera al empezar y al terminar la semana (0–1).
  final double weightStart;
  final double weightEnd;

  /// Cuántos puntos porcentuales le aportó a la variación de la cartera.
  /// La suma de todas las posiciones da [WeeklyPortfolioNumbers.changePct].
  final double contributionPp;

  /// Movimiento del precio de la acción en la semana (viernes contra viernes),
  /// sin importar cuándo compró el usuario. `null` si falta el cierre previo.
  final double? pricePct;

  /// Alguna compra de este ticker fue durante la semana.
  final bool boughtThisWeek;

  double get changeAbs => valueEnd - valueStart;

  /// Variación de la posición del usuario (desde su compra si fue en la
  /// semana).
  double get positionPct => valueStart > 0 ? changeAbs / valueStart * 100 : 0;
}

/// Una posición cerrada durante la semana (solo informativo).
class WeeklyClosedPosition {
  const WeeklyClosedPosition({
    required this.ticker,
    required this.pnlAbsolute,
    required this.pnlPercent,
  });

  final String ticker;
  final double pnlAbsolute;
  final double pnlPercent;
}

/// La posición más grande ahora y su peso cuatro semanas antes.
class WeeklyConcentration {
  const WeeklyConcentration({
    required this.ticker,
    required this.weightNow,
    this.weightFourWeeksAgo,
  });

  final String ticker;
  final double weightNow;

  /// `null` si no la tenía o no hay precios de entonces.
  final double? weightFourWeeksAgo;
}

/// Un punto del gráfico de la semana: variación acumulada desde el cierre del
/// viernes anterior (0 %) hasta ese día.
class WeeklyDayPoint {
  const WeeklyDayPoint({
    required this.day,
    required this.portfolioPct,
    this.sp500Pct,
  });

  final DateTime day;
  final double portfolioPct;
  final double? sp500Pct;
}

/// Los números de la semana: todo lo que el informe muestra en cifras. El
/// LLM nunca produce ninguno de estos valores; solo los lee.
class WeeklyPortfolioNumbers {
  const WeeklyPortfolioNumbers({
    required this.week,
    required this.valueStart,
    required this.valueEnd,
    required this.newMoney,
    required this.positions,
    required this.tradingDays,
    required this.missingPrices,
    this.sp500Pct,
    this.concentration,
    this.closedThisWeek = const [],
    this.daily = const [],
  });

  final ReportWeek week;
  final double valueStart;
  final double valueEnd;

  /// Lo que compró durante la semana, a costo. Ya está dentro de
  /// [valueStart], así que no cuenta como ganancia.
  final double newMoney;

  /// Ordenadas por impacto: de mayor a menor |contribución|.
  final List<WeeklyPositionMove> positions;

  /// Ruedas con precio en la semana (4 con un feriado).
  final int tradingDays;

  /// Tickers que quedaron afuera porque no tienen cierre en la semana.
  final List<String> missingPrices;

  /// Variación del S&P 500 en la misma semana. `null` sin datos.
  final double? sp500Pct;

  /// `null` con menos de 2 posiciones: con una sola no hay concentración
  /// que contar.
  final WeeklyConcentration? concentration;

  final List<WeeklyClosedPosition> closedThisWeek;

  /// El viernes anterior (0 %) y cada rueda de la semana. Vacío si no hay
  /// velas suficientes.
  final List<WeeklyDayPoint> daily;

  double get changeAbs => valueEnd - valueStart;
  double get changePct => valueStart > 0 ? changeAbs / valueStart * 100 : 0;

  /// Diferencia contra el S&P en puntos porcentuales.
  double? get vsSp500Pp => sp500Pct == null ? null : changePct - sp500Pct!;

  bool get isEmpty => positions.isEmpty;
}

/// Calcula [WeeklyPortfolioNumbers] a partir de las compras y los cierres
/// diarios. Sin red ni reloj: todo entra por parámetro.
abstract final class WeeklyPortfolioCalculator {
  static WeeklyPortfolioNumbers compute({
    required ReportWeek week,
    required List<Position> lots,
    required Map<String, List<PriceCandle>> candles,
    List<PriceCandle> benchmark = const [],
    List<ClosedPosition> closed = const [],
  }) {
    final starts = <String, double>{};
    final ends = <String, double>{};
    final bought = <String>{};
    final missing = <String>{};
    var newMoney = 0.0;

    for (final lot in lots) {
      final ticker = PortfolioCalculator.normalizeTicker(lot.ticker);
      final buy = _day(lot.purchaseDate);
      if (buy.isAfter(week.friday)) continue; // compró después de la semana
      final series = candles[ticker] ?? const <PriceCandle>[];
      final endPrice = _closeOnOrBefore(series, week.friday);
      if (endPrice == null) {
        missing.add(ticker);
        continue;
      }
      final double start;
      if (buy.isBefore(week.monday)) {
        start =
            lot.quantity *
            (_closeBefore(series, week.monday) ?? lot.purchasePrice);
      } else {
        start = lot.costBasis;
        newMoney += start;
        bought.add(ticker);
      }
      starts[ticker] = (starts[ticker] ?? 0) + start;
      ends[ticker] = (ends[ticker] ?? 0) + lot.quantity * endPrice;
    }
    // Un ticker con algún lote valuado no está "sin precio".
    missing.removeAll(starts.keys);

    final totalStart = starts.values.fold(0.0, (a, b) => a + b);
    final totalEnd = ends.values.fold(0.0, (a, b) => a + b);

    final positions = [
      for (final ticker in starts.keys)
        WeeklyPositionMove(
          ticker: ticker,
          valueStart: starts[ticker]!,
          valueEnd: ends[ticker]!,
          weightStart: totalStart > 0 ? starts[ticker]! / totalStart : 0,
          weightEnd: totalEnd > 0 ? ends[ticker]! / totalEnd : 0,
          contributionPp:
              totalStart > 0
                  ? (ends[ticker]! - starts[ticker]!) / totalStart * 100
                  : 0,
          pricePct: _weekPct(candles[ticker] ?? const [], week),
          boughtThisWeek: bought.contains(ticker),
        ),
    ]..sort((a, b) => b.contributionPp.abs().compareTo(a.contributionPp.abs()));

    return WeeklyPortfolioNumbers(
      week: week,
      valueStart: totalStart,
      valueEnd: totalEnd,
      newMoney: newMoney,
      positions: positions,
      tradingDays: _tradingDays(
        benchmark.isNotEmpty ? [benchmark] : candles.values,
        week,
      ),
      missingPrices: missing.toList()..sort(),
      sp500Pct: _weekPct(benchmark, week),
      concentration: _concentration(week, lots, candles, positions),
      daily: _daily(week, lots, candles, benchmark),
      closedThisWeek: [
        for (final c in closed)
          if (!_day(c.closeDate).isBefore(week.monday) &&
              !_day(c.closeDate).isAfter(week.friday))
            WeeklyClosedPosition(
              ticker: PortfolioCalculator.normalizeTicker(c.ticker),
              pnlAbsolute: c.pnlAbsolute,
              pnlPercent: c.pnlPercent,
            ),
      ],
    );
  }

  /// Cada rueda: valor de lo que tenía ese día contra su valor al empezar la
  /// semana (lo comprado en la semana entra a costo el día de la compra,
  /// igual que en [compute]: la plata nueva no es ganancia). Al viernes
  /// coincide con [WeeklyPortfolioNumbers.changePct].
  static List<WeeklyDayPoint> _daily(
    ReportWeek week,
    List<Position> lots,
    Map<String, List<PriceCandle>> candles,
    List<PriceCandle> benchmark,
  ) {
    final days =
        {
            for (final series
                in benchmark.isNotEmpty ? [benchmark] : candles.values)
              for (final c in series)
                if (!_candleDay(c).isBefore(week.monday) &&
                    !_candleDay(c).isAfter(week.friday))
                  _candleDay(c),
          }.toList()
          ..sort();
    if (days.isEmpty) return const [];
    final spStart = _closeBefore(benchmark, week.monday);

    double? portfolioPctOn(DateTime day) {
      var start = 0.0;
      var value = 0.0;
      for (final lot in lots) {
        final buy = _day(lot.purchaseDate);
        if (buy.isAfter(day)) continue;
        final series =
            candles[PortfolioCalculator.normalizeTicker(lot.ticker)] ??
            const <PriceCandle>[];
        final close = _closeOnOrBefore(series, day);
        if (close == null) continue;
        start +=
            buy.isBefore(week.monday)
                ? lot.quantity *
                    (_closeBefore(series, week.monday) ?? lot.purchasePrice)
                : lot.costBasis;
        value += lot.quantity * close;
      }
      return start > 0 ? (value - start) / start * 100 : null;
    }

    double? spPctOn(DateTime day) {
      final close = _closeOnOrBefore(benchmark, day);
      if (spStart == null || close == null || spStart <= 0) return null;
      return (close - spStart) / spStart * 100;
    }

    final previousFriday = DateTime(
      week.monday.year,
      week.monday.month,
      week.monday.day - 3,
    );
    final points = <WeeklyDayPoint>[
      WeeklyDayPoint(
        day: previousFriday,
        portfolioPct: 0,
        sp500Pct: spStart == null ? null : 0,
      ),
    ];
    for (final day in days) {
      final pct = portfolioPctOn(day);
      if (pct == null) continue;
      points.add(
        WeeklyDayPoint(day: day, portfolioPct: pct, sp500Pct: spPctOn(day)),
      );
    }
    return points.length >= 2 ? points : const [];
  }

  static WeeklyConcentration? _concentration(
    ReportWeek week,
    List<Position> lots,
    Map<String, List<PriceCandle>> candles,
    List<WeeklyPositionMove> positions,
  ) {
    if (positions.length < 2) return null;
    final top = positions.reduce((a, b) => b.weightEnd > a.weightEnd ? b : a);

    // Cuatro semanas antes del viernes: misma cuenta con lo que tenía ese día.
    final then = DateTime(
      week.friday.year,
      week.friday.month,
      week.friday.day - 28,
    );
    final values = <String, double>{};
    for (final lot in lots) {
      if (_day(lot.purchaseDate).isAfter(then)) continue;
      final ticker = PortfolioCalculator.normalizeTicker(lot.ticker);
      final price = _closeOnOrBefore(candles[ticker] ?? const [], then);
      if (price == null) continue;
      values[ticker] = (values[ticker] ?? 0) + lot.quantity * price;
    }
    final total = values.values.fold(0.0, (a, b) => a + b);
    final topThen = values[top.ticker];
    return WeeklyConcentration(
      ticker: top.ticker,
      weightNow: top.weightEnd,
      weightFourWeeksAgo:
          total > 0 && topThen != null && values.length >= 2
              ? topThen / total
              : null,
    );
  }

  /// Viernes contra viernes anterior.
  static double? _weekPct(List<PriceCandle> series, ReportWeek week) {
    final start = _closeBefore(series, week.monday);
    final end = _closeOnOrBefore(series, week.friday);
    if (start == null || end == null || start <= 0) return null;
    // Sin ninguna rueda en la semana, el "cierre del viernes" es el mismo
    // del viernes anterior: no hubo semana que medir.
    if (!_hasCandleIn(series, week)) return null;
    return (end - start) / start * 100;
  }

  static int _tradingDays(
    Iterable<List<PriceCandle>> seriesList,
    ReportWeek week,
  ) {
    final days = <DateTime>{};
    for (final series in seriesList) {
      for (final c in series) {
        final d = _candleDay(c);
        if (!d.isBefore(week.monday) && !d.isAfter(week.friday)) days.add(d);
      }
    }
    return days.length;
  }

  static bool _hasCandleIn(List<PriceCandle> series, ReportWeek week) =>
      series.any((c) {
        final d = _candleDay(c);
        return !d.isBefore(week.monday) && !d.isAfter(week.friday);
      });

  /// Último cierre en un día anterior a [day].
  static double? _closeBefore(List<PriceCandle> series, DateTime day) {
    double? close;
    DateTime? best;
    for (final c in series) {
      final d = _candleDay(c);
      if (d.isBefore(day) && (best == null || d.isAfter(best))) {
        best = d;
        close = c.close;
      }
    }
    return close;
  }

  /// Último cierre en [day] o antes.
  static double? _closeOnOrBefore(List<PriceCandle> series, DateTime day) =>
      _closeBefore(series, DateTime(day.year, day.month, day.day + 1));

  /// Fecha de calendario local (compras y cierres que carga el usuario).
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Día bursátil de una vela diaria. Yahoo la fecha con el timestamp de la
  /// apertura (13:30–14:30 UTC) convertido a hora local: en UTC+10 eso ya es
  /// el día siguiente. En UTC es el día correcto en cualquier zona horaria.
  static DateTime _candleDay(PriceCandle c) {
    final u = c.date.toUtc();
    return DateTime(u.year, u.month, u.day);
  }
}
