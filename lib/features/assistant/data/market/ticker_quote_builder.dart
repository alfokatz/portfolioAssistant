import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/utils/ticker_period_utils.dart';

/// Precio actual + variación por período + disponibilidad de gráfico de un
/// ticker (Yahoo, vía [QuoteRepository]).
abstract final class TickerQuoteBuilder {
  static const periods = <String, ({String labelEs, Duration duration})>{
    'day': (labelEs: 'último día', duration: Duration(days: 1)),
    'week': (labelEs: 'últimos 7 días', duration: Duration(days: 7)),
    'month': (labelEs: 'últimos 30 días', duration: Duration(days: 30)),
    'quarter': (labelEs: 'últimos 90 días', duration: Duration(days: 90)),
    'year': (labelEs: 'último año', duration: Duration(days: 365)),
  };

  static Future<Map<String, Object?>> build({
    required String ticker,
    required QuoteRepository quoteRepository,
  }) async {
    final priceResult = await quoteRepository.getCurrentPrice(ticker);
    if (priceResult.isLeft()) {
      return {'fetch_ok': false};
    }

    final currentPrice = priceResult.getOrElse(() => 0.0);
    final candlesResult = await quoteRepository.getHistoricalDaily(ticker);
    final history = candlesResult.fold((_) => <PriceCandle>[], (list) => list);

    final periodsMap = <String, Object?>{};
    for (final entry in periods.entries) {
      final move = TickerPeriodUtils.moveForDuration(
        history,
        entry.value.duration,
      );
      periodsMap[entry.key] = {
        'change_pct': _round2(move.changePct),
        'price_start': _round2(move.priceStart),
        'price_end': _round2(move.priceEnd),
        'has_sufficient_history': move.hasSufficientHistory,
        'label_es': entry.value.labelEs,
      };
    }

    return {
      'current_price': _round2(currentPrice),
      'fetch_ok': true,
      // `QaPriceChart` trae la serie sola dentro de la app; esto solo dice
      // si hay histórico diario para trazar una línea (si no, el widget
      // correcto es QaTickerSnapshot/QaTickerMove).
      'price_chart_available': history.length >= 2,
      'periods': periodsMap,
    };
  }

  static double _round2(double value) => double.parse(value.toStringAsFixed(2));
}
