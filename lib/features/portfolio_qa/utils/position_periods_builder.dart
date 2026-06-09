import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/utils/ticker_period_utils.dart';

/// Períodos de precio por ticker para el snapshot del asistente QA.
abstract final class PositionPeriodsBuilder {
  static const _periods = <String, ({String labelEs, Duration duration})>{
    'day': (labelEs: 'último día', duration: Duration(days: 1)),
    'week': (labelEs: 'últimos 7 días', duration: Duration(days: 7)),
    'month': (labelEs: 'últimos 30 días', duration: Duration(days: 30)),
    'quarter': (labelEs: 'últimos 90 días', duration: Duration(days: 90)),
    'year': (labelEs: 'último año', duration: Duration(days: 365)),
  };

  static Future<Map<String, Map<String, Object?>>> build({
    required PortfolioSummary summary,
    required QuoteRepository quoteRepository,
  }) async {
    final tickers =
        summary.valuations.map((v) => v.position.ticker).toSet().toList();
    final result = <String, Map<String, Object?>>{};

    for (final ticker in tickers) {
      final candles = await quoteRepository.getHistoricalDaily(ticker);
      final history = candles.fold(
        (_) => <PriceCandle>[],
        (list) => list,
      );
      final periodsMap = <String, Object?>{};

      for (final entry in _periods.entries) {
        final move = TickerPeriodUtils.moveForDuration(
          history,
          entry.value.duration,
        );
        periodsMap[entry.key] = {
          'label_es': entry.value.labelEs,
          'price_start': _round2(move.priceStart),
          'price_end': _round2(move.priceEnd),
          'change_abs': _round2(move.changeAbs),
          'change_pct': _round2(move.changePct),
          'has_sufficient_history': move.hasSufficientHistory,
        };
      }

      result[ticker] = periodsMap;
    }

    return result;
  }

  static double _round2(double value) =>
      double.parse(value.toStringAsFixed(2));
}
