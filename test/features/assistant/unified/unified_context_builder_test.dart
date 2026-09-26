import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_earnings_enricher.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_news_enricher.dart';
import 'package:portfolio_assistant/features/assistant/unified/message_needs.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_context_builder.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_snapshot_validator.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_turn_history.dart';

import 'unified_test_fakes.dart';

void main() {
  final asOf = DateTime.utc(2026, 9, 25, 12);

  Future<Map<String, Object?>> build(
    String message, {
    required CountingQuoteRepository quotes,
    bool marketData = true,
    bool news = true,
    FakeCompanyNewsRepository? newsRepo,
    FakeEarningsCalendarRepository? earningsRepo,
    String? followUp,
  }) async {
    final needs = await MessageNeedsAnalyzer.analyze(
      message: message,
      summary: heldSummary,
      followUpTicker: followUp,
    );
    return UnifiedContextBuilder.build(
      needs: needs,
      userMessage: message,
      quoteRepository: quotes,
      marketDataAllowed: marketData,
      newsAllowed: news,
      summary: heldSummary,
      newsEnricher:
          news
              ? ExploreNewsEnricher(
                newsRepository: newsRepo ?? FakeCompanyNewsRepository(),
              )
              : null,
      earningsEnricher:
          news
              ? ExploreEarningsEnricher(
                earningsRepository:
                    earningsRepo ?? FakeEarningsCalendarRepository(),
              )
              : null,
      asOf: asOf,
    );
  }

  group('only what the message needs is fetched', () {
    test(
      'a conceptual question with a ticker example fetches NO prices',
      () async {
        final quotes = CountingQuoteRepository();
        final snapshot = await build(
          '¿Qué es un ETF, como SPY?',
          quotes: quotes,
        );
        expect(quotes.priceCalls, isEmpty);
        expect(quotes.dailyCalls, isEmpty);
        expect(snapshot['tickers'], isEmpty);
        expect(snapshot.containsKey('news_enrichment'), isFalse);
        expect(snapshot.containsKey('earnings_calendar_status'), isFalse);
      },
    );

    test(
      'a portfolio question fetches no ticker prices, but has the portfolio',
      () async {
        final quotes = CountingQuoteRepository();
        final snapshot = await build('¿Cómo está mi cartera?', quotes: quotes);
        expect(quotes.priceCalls, isEmpty);
        expect(quotes.dailyCalls, isEmpty);
        final portfolio = snapshot['portfolio'] as Map;
        expect(portfolio['has_positions'], isTrue);
        expect((portfolio['positions'] as List), hasLength(2));
        expect(portfolio['position_periods'], isEmpty);
      },
    );

    test(
      'a held ticker gets its ticker entry AND position_periods for only that ticker',
      () async {
        final quotes = CountingQuoteRepository();
        final snapshot = await build(
          '¿Cómo fue AAPL esta semana?',
          quotes: quotes,
        );
        final aapl = (snapshot['tickers'] as Map)['AAPL'] as Map;
        expect(aapl['held'], isTrue);
        expect(aapl['fetch_ok'], isTrue);
        expect(aapl['price_chart_available'], isTrue);
        expect(aapl['weight_pct'], isNotNull);
        final periods =
            (snapshot['portfolio'] as Map)['position_periods'] as Map;
        expect(periods.keys, ['AAPL']);
      },
    );

    test('B4 fetches position_periods for ALL holdings', () async {
      final quotes = CountingQuoteRepository();
      final snapshot = await build(
        '¿Cuál de mis acciones subió más esta semana?',
        quotes: quotes,
      );
      final periods = (snapshot['portfolio'] as Map)['position_periods'] as Map;
      expect(periods.keys.toSet(), {'AAPL', 'NVDA'});
      expect(snapshot['tickers'], isEmpty);
    });

    test('an external ticker is marked held=false', () async {
      final snapshot = await build(
        '¿A cuánto está TSLA?',
        quotes: CountingQuoteRepository(),
      );
      final tsla = (snapshot['tickers'] as Map)['TSLA'] as Map;
      expect(tsla['held'], isFalse);
      expect(tsla.containsKey('weight_pct'), isFalse);
    });

    test(
      'without market data access an external ticker is never fetched',
      () async {
        final quotes = CountingQuoteRepository();
        final snapshot = await build(
          'comparame AAPL y TSLA',
          quotes: quotes,
          marketData: false,
          news: false,
        );
        expect(quotes.priceCalls, isNot(contains('TSLA')));
        expect((snapshot['tickers'] as Map).keys, ['AAPL']);
        expect(snapshot['access'], {'market_data': false, 'news': false});
      },
    );
  });

  group('snapshot shape', () {
    test('one shape, one name, no mode keys', () async {
      final snapshot = await build(
        '¿A cuánto está AAPL?',
        quotes: CountingQuoteRepository(),
      );
      expect(
        snapshot.keys.toSet(),
        containsAll(['as_of', 'access', 'portfolio', 'tickers']),
      );
      for (final legacy in const [
        'mode',
        'explore_tickers',
        'portfolio_context',
        'portfolio_fit',
      ]) {
        expect(snapshot.containsKey(legacy), isFalse, reason: legacy);
      }
    });

    test('the market proxy is labeled', () async {
      final snapshot = await build(
        '¿Cómo está el mercado hoy?',
        quotes: CountingQuoteRepository(),
      );
      expect(snapshot['market_proxy_ticker'], 'SPY');
      expect(snapshot['market_proxy_label'], contains('S&P 500'));
    });
  });

  group('news and earnings', () {
    test(
      'an explicit news request with access runs the news enricher on the tickers',
      () async {
        final newsRepo = FakeCompanyNewsRepository();
        final snapshot = await build(
          '¿Qué noticias hay de AAPL?',
          quotes: CountingQuoteRepository(),
          newsRepo: newsRepo,
        );
        expect(newsRepo.calls, ['AAPL']);
        expect(snapshot['news_enrichment'], 'ok');
        expect(snapshot['news_sources'], hasLength(1));
      },
    );

    test(
      'without news access: news and earnings are "locked", nothing is fetched',
      () async {
        final snapshot = await build(
          '¿Qué noticias hay de AAPL?',
          quotes: CountingQuoteRepository(),
          news: false,
        );
        expect(snapshot['news_enrichment'], 'locked');
        expect(snapshot['earnings_calendar_status'], 'locked');
      },
    );

    test(
      'the follow-up ticker feeds the news fetch ("¿y las noticias?")',
      () async {
        final newsRepo = FakeCompanyNewsRepository();
        await build(
          '¿Y las noticias?',
          quotes: CountingQuoteRepository(),
          newsRepo: newsRepo,
          followUp: 'NVDA',
        );
        expect(newsRepo.calls, ['NVDA']);
      },
    );
  });

  group('UnifiedTurnHistory', () {
    test('takes the most recent assistant turn that resolved a ticker', () {
      final messages = [
        const PortfolioQaMessage(
          role: PortfolioQaRole.assistant,
          subjectTickers: ['AAPL'],
        ),
        const PortfolioQaMessage(
          role: PortfolioQaRole.user,
          content: '¿qué es un ETF?',
        ),
        const PortfolioQaMessage(role: PortfolioQaRole.assistant),
        const PortfolioQaMessage(
          role: PortfolioQaRole.user,
          content: '¿y las noticias?',
        ),
      ];
      expect(UnifiedTurnHistory.followUpTicker(messages), 'AAPL');
    });

    test('null when no turn resolved a ticker', () {
      expect(
        UnifiedTurnHistory.followUpTicker(const [
          PortfolioQaMessage(role: PortfolioQaRole.assistant, content: 'hola'),
        ]),
        isNull,
      );
    });
  });

  group('UnifiedSnapshotValidator — the only pre-model cut', () {
    test('cuts when every requested ticker failed', () async {
      final snapshot = await build(
        '¿A cuánto está TSLA?',
        quotes: CountingQuoteRepository(failing: {'TSLA'}),
      );
      expect(
        UnifiedSnapshotValidator.allRequestedTickersFailed(snapshot),
        isTrue,
      );
    });

    test(
      'does not cut conceptual, portfolio-only, or partially failed questions',
      () async {
        for (final message in const [
          '¿Qué es un ETF?',
          '¿Cómo está mi cartera?',
        ]) {
          final snapshot = await build(
            message,
            quotes: CountingQuoteRepository(),
          );
          expect(
            UnifiedSnapshotValidator.allRequestedTickersFailed(snapshot),
            isFalse,
            reason: message,
          );
        }
        final partial = await build(
          'comparame AAPL y TSLA',
          quotes: CountingQuoteRepository(failing: {'TSLA'}),
        );
        expect(
          UnifiedSnapshotValidator.allRequestedTickersFailed(partial),
          isFalse,
        );
      },
    );

    test('does not cut an ambiguous company name (the model asks)', () {
      expect(
        UnifiedSnapshotValidator.allRequestedTickersFailed({
          'tickers': <String, Object?>{},
          'ticker_ambiguous': {'candidate': 'Meta'},
        }),
        isFalse,
      );
    });
  });
}
