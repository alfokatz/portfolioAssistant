import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_intraday.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

/// La serie del período "1D" de la Home (ver [PortfolioIntraday.series]).
/// Pide las velas de 5 min solo de los tickers de más valor y solo cuando
/// alguien mira el 1D (autoDispose). `null` sin al menos dos días de
/// historial; si las velas fallan, la recta entre el cierre anterior y hoy.
final homeIntradayProvider =
    FutureProvider.autoDispose<List<PortfolioHistoryPoint>?>((ref) async {
      final history = ref.watch(homeProvider.select((s) => s.history));
      final valuations = ref.watch(
        homeProvider.select((s) => s.summary?.valuations ?? const []),
      );
      if (history.length < 2) return null;
      final previous = history[history.length - 2];
      final last = history.last;

      final byTicker = <String, ({double quantity, double price})>{};
      for (final v in valuations) {
        final ticker = PortfolioCalculator.normalizeTicker(v.position.ticker);
        final prev = byTicker[ticker];
        byTicker[ticker] = (
          quantity: (prev?.quantity ?? 0) + v.position.quantity,
          price: v.currentPrice,
        );
      }
      final base = [
        for (final MapEntry(key: ticker, value: h) in byTicker.entries)
          IntradayHolding(
            ticker: ticker,
            quantity: h.quantity,
            lastPrice: h.price,
          ),
      ];

      final quotes = ref.read(quoteRepositoryProvider);
      final candles = <String, List<PriceCandle>>{};
      await Future.wait([
        for (final ticker in PortfolioIntraday.topTickers(base))
          quotes
              .getIntradayCandles(ticker)
              .timeout(const Duration(seconds: 6))
              .then((c) => candles[ticker] = c)
              .catchError((Object _) => const <PriceCandle>[]),
      ]);

      return PortfolioIntraday.series(
        previous: previous,
        last: last,
        holdings: [
          for (final h in base)
            IntradayHolding(
              ticker: h.ticker,
              quantity: h.quantity,
              lastPrice: h.lastPrice,
              candles: candles[h.ticker],
            ),
        ],
      );
    });
