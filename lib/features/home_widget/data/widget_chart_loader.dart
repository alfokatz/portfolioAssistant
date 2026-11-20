import 'dart:async';

import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_chart_builder.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_phrase.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot.dart';

/// Arma el gráfico del widget (spec home-widget-v2-tech §4.5) con las velas
/// diarias que ya se cargaron y las intradía de los tickers de más valor.
/// Lo usan la app abierta y el refresco de fondo. Nunca tira: sin datos
/// devuelve `null` y el widget sigue sin gráfico.
Future<WidgetChart?> loadWidgetChart({
  required List<Position> positions,
  required Map<String, List<PriceCandle>> dailyCandles,
  required double movePercent,
  required List<double> dailyValues,
  required Future<List<PriceCandle>> Function(String ticker)? loadIntraday,
  Duration timeout = const Duration(seconds: 6),
}) async {
  try {
    final quantities = <String, double>{};
    for (final p in positions) {
      quantities[p.ticker] = (quantities[p.ticker] ?? 0) + p.quantity;
    }
    final base = <WidgetChartHolding>[
      for (final MapEntry(key: ticker, value: quantity) in quantities.entries)
        if (_last(dailyCandles[ticker]) case final last?)
          WidgetChartHolding(
            ticker: ticker,
            quantity: quantity,
            lastPrice: last.close,
          ),
    ];
    final direction = WidgetDirection.fromPercent(movePercent);

    final load = loadIntraday;
    if (load == null || base.isEmpty) {
      return WidgetChartBuilder.build(
        holdings: base,
        direction: direction,
        dailyValues: dailyValues,
      );
    }

    final top = WidgetChartBuilder.topTickers(base).toSet();
    final intraday = <String, List<PriceCandle>>{};
    await Future.wait([
      for (final ticker in top)
        load(ticker)
            .timeout(timeout)
            .then((c) => intraday[ticker] = c)
            .catchError((Object _) => const <PriceCandle>[]),
    ]);

    final holdings = <WidgetChartHolding>[
      for (final h in base)
        _withIntraday(h, intraday[h.ticker], dailyCandles[h.ticker]),
    ];
    return WidgetChartBuilder.build(
      holdings: holdings,
      direction: direction,
      dailyValues: dailyValues,
    );
  } catch (_) {
    return null;
  }
}

/// Le agrega a [h] su serie intradía y el cierre anterior: el de la última
/// vela diaria de un día anterior al de la serie.
WidgetChartHolding _withIntraday(
  WidgetChartHolding h,
  List<PriceCandle>? intraday,
  List<PriceCandle>? daily,
) {
  if (intraday == null || intraday.isEmpty) return h;
  final points = [
    for (final c in intraday)
      if (c.close > 0) (time: c.date, price: c.close),
  ]..sort((a, b) => a.time.compareTo(b.time));
  if (points.isEmpty) return h;
  final first = points.first.time.toLocal();
  final day = DateTime(first.year, first.month, first.day);
  PriceCandle? prev;
  for (final c in daily ?? const <PriceCandle>[]) {
    final d = c.date.toLocal();
    if (!DateTime(d.year, d.month, d.day).isBefore(day)) continue;
    if (prev == null || c.date.isAfter(prev.date)) prev = c;
  }
  return WidgetChartHolding(
    ticker: h.ticker,
    quantity: h.quantity,
    lastPrice: points.last.price,
    prevClose: prev?.close,
    intraday: points,
  );
}

PriceCandle? _last(List<PriceCandle>? candles) {
  if (candles == null || candles.isEmpty) return null;
  var best = candles.first;
  for (final c in candles) {
    if (c.date.isAfter(best.date)) best = c;
  }
  return best;
}
