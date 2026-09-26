import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_snapshot_builder.dart';

/// Caracterización del CONTEXTO que arma cada modo hoy (antes de la
/// unificación). Complementa `assistant_mode_snapshot_test.dart`: fija lo
/// que ese test no cubre y que el context builder unificado tiene que
/// preservar o cambiar a propósito.
class _CountingQuoteRepository implements QuoteRepository {
  final dailyCalls = <String>[];
  int priceCalls = 0;

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async {
    priceCalls++;
    return const Right(150);
  }

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) async {
    dailyCalls.add(ticker);
    final end = DateTime(2026, 9, 25);
    return Right([
      for (var i = 0; i < 400; i++)
        PriceCandle(
          date: end.subtract(Duration(days: 399 - i)),
          close: 100.0 + i / 10,
        ),
    ]);
  }

  @override
  Future<List<PriceCandle>> getIntradayCandles(String ticker) async => const [];
}

PositionValuation _valuation(String ticker) => PositionValuation(
  position: Position(
    id: ticker,
    ticker: ticker,
    quantity: 2,
    purchasePrice: 100,
    purchaseDate: DateTime(2024, 1, 1),
  ),
  currentPrice: 150,
  marketValue: 300,
  pnlAbsolute: 100,
  pnlPercent: 50,
);

final _summary = PortfolioSummary(
  totalValue: 600,
  totalCostBasis: 400,
  totalPnlAbsolute: 200,
  totalPnlPercent: 50,
  valuations: [_valuation('NVDA'), _valuation('AAPL')],
);

final _asOf = DateTime.utc(2026, 9, 25, 12);

void main() {
  group('Portfolio mode context', () {
    test('CTX-PF-1: snapshot is FLAT — portfolio fields at the root, no '
        'portfolio_context wrapper', () async {
      final snapshot =
          jsonDecode(
                await buildSnapshotJson(
                  mode: AssistantMode.portfolio,
                  summary: _summary,
                  quoteRepository: _CountingQuoteRepository(),
                  asOf: _asOf,
                ),
              )
              as Map<String, dynamic>;

      expect(snapshot.containsKey('portfolio_context'), isFalse);
      for (final key in const [
        'has_positions',
        'has_closed_positions',
        'has_portfolio_data',
        'total_value',
        'total_cost_basis',
        'total_pnl_abs',
        'total_pnl_pct',
        'pnl_scope',
        'period_returns',
        'position_periods',
        'positions',
        'closed_positions',
        'closed_pnl_total_abs',
        'closed_pnl_total_cost_basis',
        'closed_pnl_total_pct',
      ]) {
        expect(snapshot.containsKey(key), isTrue, reason: key);
      }
    });

    test('CTX-PF-2: position_periods is built ONLY here — one daily-history '
        'fetch per HELD ticker, with all five periods', () async {
      final repo = _CountingQuoteRepository();
      final snapshot =
          jsonDecode(
                await buildSnapshotJson(
                  mode: AssistantMode.portfolio,
                  summary: _summary,
                  quoteRepository: repo,
                  asOf: _asOf,
                ),
              )
              as Map<String, dynamic>;

      expect(repo.dailyCalls.toSet(), {'NVDA', 'AAPL'});
      final periods = snapshot['position_periods'] as Map<String, dynamic>;
      expect(periods.keys.toSet(), {'NVDA', 'AAPL'});
      expect(
        (periods['NVDA'] as Map).keys.toSet(),
        containsAll(['day', 'week', 'month', 'quarter', 'year']),
      );
    });

    test('CTX-PF-3: no news, earnings, or non-held ticker data', () async {
      final snapshot =
          jsonDecode(
                await buildSnapshotJson(
                  mode: AssistantMode.portfolio,
                  summary: _summary,
                  quoteRepository: _CountingQuoteRepository(),
                  asOf: _asOf,
                  userMessage: '¿qué pasó con TSLA?',
                ),
              )
              as Map<String, dynamic>;

      for (final key in const [
        'explore_tickers',
        'news_sources',
        'news_enrichment',
        'earnings_calendar',
        'earnings_calendar_status',
      ]) {
        expect(snapshot.containsKey(key), isFalse, reason: key);
      }
    });
  });

  group('Learn mode context', () {
    test('CTX-LN-1: exactly {mode, as_of, portfolio_context} and it never '
        'touches quotes, even with a ticker in the message', () async {
      final repo = _CountingQuoteRepository();
      final snapshot =
          jsonDecode(
                await buildSnapshotJson(
                  mode: AssistantMode.learn,
                  summary: _summary,
                  quoteRepository: repo,
                  asOf: _asOf,
                  userMessage: '¿Qué es un ETF, como SPY?',
                ),
              )
              as Map<String, dynamic>;

      expect(snapshot.keys.toSet(), {'mode', 'as_of', 'portfolio_context'});
      expect(repo.dailyCalls, isEmpty);
      expect(repo.priceCalls, 0);
    });
  });

  group('portfolio_context outside Portfolio mode', () {
    test('CTX-SHARED-1: holdings are present but position_periods is EMPTY in '
        'Learn and Explore (only Portfolio fetches it)', () async {
      for (final mode in [AssistantMode.learn, AssistantMode.explore]) {
        final snapshot =
            jsonDecode(
                  await buildSnapshotJson(
                    mode: mode,
                    summary: _summary,
                    quoteRepository: _CountingQuoteRepository(),
                    asOf: _asOf,
                    userMessage: 'hola',
                    enableNewsEnrichment: false,
                    enableEarningsCalendar: false,
                  ),
                )
                as Map<String, dynamic>;

        final context = snapshot['portfolio_context'] as Map<String, dynamic>;
        expect((context['positions'] as List), hasLength(2), reason: '$mode');
        expect(context['position_periods'], isEmpty, reason: '$mode');
      }
    });
  });
}
