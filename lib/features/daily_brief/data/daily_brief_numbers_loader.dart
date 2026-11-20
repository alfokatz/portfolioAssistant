import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_numbers.dart';

/// Trae las velas diarias de cada posición (Yahoo, vía el repositorio de
/// cotizaciones) y arma los números del brief con [DailyBriefNumbers]. El
/// historial es el de la Home: la variación sale de ahí, no de las velas.
/// Nunca lanza: un ticker sin velas queda fuera de los movers.
class DailyBriefNumbersLoader {
  DailyBriefNumbersLoader({required QuoteRepository quotes}) : _quotes = quotes;

  final QuoteRepository _quotes;

  Future<DailyBriefNumbers> load({
    required List<PortfolioHistoryPoint> history,
    required List<Position> lots,
    DateTime? now,
  }) async {
    if (history.length < 2) {
      return DailyBriefNumbers.compute(
        history: history,
        lots: lots,
        candlesByTicker: const {},
        now: now,
      );
    }
    final tickers = {for (final p in lots) p.ticker}.toList();
    final series = await Future.wait([for (final t in tickers) _candles(t)]);
    return DailyBriefNumbers.compute(
      history: history,
      lots: lots,
      candlesByTicker: {
        for (var i = 0; i < tickers.length; i++)
          if (series[i] != null) tickers[i]: series[i]!,
      },
      now: now,
    );
  }

  Future<List<PriceCandle>?> _candles(String ticker) async {
    try {
      final result = await _quotes.getHistoricalDaily(ticker);
      return result.fold<List<PriceCandle>?>((_) => null, (c) => c);
    } catch (_) {
      return null;
    }
  }
}
