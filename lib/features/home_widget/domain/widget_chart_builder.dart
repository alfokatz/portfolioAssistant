import 'package:portfolio_assistant/features/home_widget/domain/widget_phrase.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot.dart';

/// Un punto de la vela intradía (5 min) de un ticker.
typedef WidgetIntradayPoint = ({DateTime time, double price});

/// Una tenencia para el gráfico del día. [intraday] es `null` si no se pidió
/// (fuera del top 10) o falló: queda fija en su precio actual.
class WidgetChartHolding {
  const WidgetChartHolding({
    required this.ticker,
    required this.quantity,
    required this.lastPrice,
    this.prevClose,
    this.intraday,
  });

  final String ticker;
  final double quantity;
  final double lastPrice;

  /// Cierre anterior (de las velas diarias ya cargadas).
  final double? prevClose;
  final List<WidgetIntradayPoint>? intraday;

  double get value => quantity * lastPrice;
}

/// La forma del día de la cartera, normalizada a 0..1: no se puede
/// reconstruir ningún monto. Puro. Docs/specs/home-widget-v2-tech.md §4.5.
abstract final class WidgetChartBuilder {
  /// Solo estos tickers (los de más valor) piden intradía.
  static const intradayTickers = 10;
  static const minGridPoints = 6;
  static const maxPoints = 48;
  static const daysPoints = 8;
  static const minDaysPoints = 3;

  /// Los [intradayTickers] de más valor: a quiénes pedirles velas.
  static List<String> topTickers(List<WidgetChartHolding> holdings) {
    final sorted = [...holdings]..sort((a, b) => b.value.compareTo(a.value));
    return [for (final h in sorted.take(intradayTickers)) h.ticker];
  }

  /// [dailyValues]: el historial diario de la cartera (el de la Home), del
  /// más viejo al más nuevo. `null` si no hay nada que dibujar.
  static WidgetChart? build({
    required List<WidgetChartHolding> holdings,
    required WidgetDirection direction,
    List<double> dailyValues = const [],
  }) {
    return _intraday(holdings, direction) ?? _days(dailyValues);
  }

  static WidgetChart? _intraday(
    List<WidgetChartHolding> holdings,
    WidgetDirection direction,
  ) {
    final sorted = [...holdings]..sort((a, b) => b.value.compareTo(a.value));
    final withSeries = [
      for (final h in sorted.take(intradayTickers))
        if ((h.intraday?.length ?? 0) >= minGridPoints) h,
    ];
    if (withSeries.isEmpty) return null;
    final grid = [for (final p in withSeries.first.intraday!) p.time];

    double priceAt(WidgetChartHolding h, DateTime time) {
      final series = h.intraday;
      final fallback = h.prevClose ?? h.lastPrice;
      // Fuera del top 10 o caído: fijo en su precio actual.
      if (series == null || series.isEmpty || !sorted.take(intradayTickers).contains(h)) {
        return h.lastPrice;
      }
      var price = fallback;
      for (final p in series) {
        if (p.time.isAfter(time)) break;
        price = p.price;
      }
      return price;
    }

    final values = <double>[
      for (final time in grid)
        holdings.fold<double>(0, (sum, h) => sum + h.quantity * priceAt(h, time)),
    ];
    final baseline = holdings.fold<double>(
      0,
      (sum, h) => sum + h.quantity * (h.prevClose ?? h.lastPrice),
    );

    final delta = values.last - baseline;
    final contradicts =
        (direction == WidgetDirection.up && delta < 0) ||
        (direction == WidgetDirection.down && delta > 0);
    if (contradicts) return null;

    final normalized = _normalize([...values, baseline]);
    return WidgetChart(
      kind: 'intraday',
      points: _reduce(normalized.sublist(0, values.length)),
      baseline: normalized.last,
    );
  }

  static WidgetChart? _days(List<double> dailyValues) {
    if (dailyValues.length < minDaysPoints) return null;
    final last =
        dailyValues.length > daysPoints
            ? dailyValues.sublist(dailyValues.length - daysPoints)
            : dailyValues;
    return WidgetChart(kind: 'days', points: _normalize(last));
  }

  /// min..max → 0..1 con 3 decimales; serie plana → todo 0.5.
  static List<double> _normalize(List<double> values) {
    var lo = values.first;
    var hi = values.first;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final span = hi - lo;
    return [
      for (final v in values)
        span <= 0 ? 0.5 : (((v - lo) / span) * 1000).round() / 1000,
    ];
  }

  /// A lo sumo [maxPoints] equiespaciados; el último se conserva.
  static List<double> _reduce(List<double> points) {
    if (points.length <= maxPoints) return points;
    return [
      for (var i = 0; i < maxPoints; i++)
        points[(i * (points.length - 1) / (maxPoints - 1)).round()],
    ];
  }
}
