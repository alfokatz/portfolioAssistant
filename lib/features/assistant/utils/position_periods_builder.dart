import 'package:portfolio_assistant/features/assistant/utils/period_labels.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/utils/ticker_period_utils.dart';

/// Períodos de precio por ticker para el snapshot del asistente QA.
abstract final class PositionPeriodsBuilder {
  static const _periods = PeriodLabels.durations;

  /// [onlyTickers] acota el cálculo a esas tenencias (un pedido de
  /// histórico por ticker); `null` = todas las posiciones abiertas.
  static Future<Map<String, Map<String, Object?>>> build({
    required PortfolioSummary summary,
    required QuoteRepository quoteRepository,
    Set<String>? onlyTickers,
  }) async {
    final tickers =
        summary.valuations
            .map((v) => v.position.ticker)
            .toSet()
            .where((t) => onlyTickers == null || onlyTickers.contains(t))
            .toList();
    final result = <String, Map<String, Object?>>{};

    for (final ticker in tickers) {
      final candles = await quoteRepository.getHistoricalDaily(ticker);
      final history = candles.fold((_) => <PriceCandle>[], (list) => list);
      final periodsMap = <String, Object?>{};

      for (final entry in _periods.entries) {
        final move = TickerPeriodUtils.moveForDuration(
          history,
          entry.value,
        );
        periodsMap[entry.key] = {
          'label_es': PeriodLabels.of(entry.key),
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

  static double _round2(double value) => double.parse(value.toStringAsFixed(2));
}
