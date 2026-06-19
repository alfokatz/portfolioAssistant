import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_context_builder.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_news_enricher.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/yahoo_ticker_search_client.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_raw_chat_client.dart';

class _FakeOpenAIRawChatClient extends OpenAIRawChatClient {
  _FakeOpenAIRawChatClient({
    required this.onSearchNews,
  }) : super(apiKey: 'test-key', model: 'test-model');

  final Future<String> Function({
    required String userQuery,
    required List<String> tickers,
  }) onSearchNews;

  @override
  Future<String> searchNews({
    required String userQuery,
    required List<String> tickers,
  }) {
    return onSearchNews(userQuery: userQuery, tickers: tickers);
  }
}

class _FakeQuoteRepository implements QuoteRepository {
  static const aaplPrice = 190.0;
  static const spyPrice = 540.0;

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async {
    if (ticker == 'AAPL') {
      return const Right(aaplPrice);
    }
    if (ticker == 'SPY') {
      return const Right(spyPrice);
    }
    if (ticker == 'BAD') {
      return Left(HttpError(code: 'not_found'));
    }
    return Left(HttpError(code: 'unknown'));
  }

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) async {
    if (ticker == 'AAPL' || ticker == 'SPY') {
      final end = DateTime(2026, 6, 10);
      final candles = List<PriceCandle>.generate(40, (i) {
        final date = end.subtract(Duration(days: 39 - i));
        return PriceCandle(date: date, close: 180.0 + i);
      });
      return Right(candles);
    }
    return Left(HttpError(code: 'not_found'));
  }
}

class _FakeQuoteRepositoryWithTtwo implements QuoteRepository {
  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async {
    if (ticker == 'TTWO') return const Right(210.0);
    return Left(HttpError(code: 'unknown'));
  }

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) async {
    if (ticker != 'TTWO') return Left(HttpError(code: 'not_found'));
    final end = DateTime(2026, 6, 10);
    return Right(
      List<PriceCandle>.generate(40, (i) {
        final date = end.subtract(Duration(days: 39 - i));
        return PriceCandle(date: date, close: 200.0 + i);
      }),
    );
  }
}

class _FakeTickerSearchClient extends YahooTickerSearchClient {
  _FakeTickerSearchClient(this._resultsByQuery) : super(dio: Dio());

  final Map<String, List<TickerSearchHit>> _resultsByQuery;

  @override
  Future<List<TickerSearchHit>> search(String query, {int limit = 3}) async {
    return _resultsByQuery[query.trim().toLowerCase()]?.take(limit).toList() ??
        const [];
  }
}

void main() {
  group('ExploreContextBuilder', () {
    final fixedAsOf = DateTime.utc(2026, 6, 10, 12, 0);
    final quoteRepository = _FakeQuoteRepository();

    test('builds snapshot with ticker data from user message', () async {
      final snapshot = await ExploreContextBuilder.build(
        userMessage: 'Cuéntame de AAPL',
        quoteRepository: quoteRepository,
        asOf: fixedAsOf,
      );

      expect(snapshot['mode'], 'explore');
      expect(snapshot['data_source'], 'yahoo_finance');
      expect(snapshot['as_of'], fixedAsOf.toIso8601String());

      final tickers = snapshot['explore_tickers'] as Map<String, dynamic>;
      expect(tickers.containsKey('AAPL'), isTrue);

      final aapl = tickers['AAPL'] as Map<String, dynamic>;
      expect(aapl['fetch_ok'], isTrue);
      expect(aapl['current_price'], _FakeQuoteRepository.aaplPrice);

      final periods = aapl['periods'] as Map<String, dynamic>;
      expect(periods.containsKey('day'), isTrue);
      expect(periods.containsKey('week'), isTrue);
      expect(periods.containsKey('month'), isTrue);

      final day = periods['day'] as Map<String, dynamic>;
      expect(day['label_es'], 'último día');
      expect(day['has_sufficient_history'], isTrue);
      expect(day.containsKey('change_pct'), isTrue);
      expect(day.containsKey('price_start'), isTrue);
      expect(day.containsKey('price_end'), isTrue);
    });

    test('marks fetch_ok false when price fetch fails', () async {
      final snapshot = await ExploreContextBuilder.build(
        userMessage: 'Analiza BAD',
        quoteRepository: quoteRepository,
        asOf: fixedAsOf,
      );

      final tickers = snapshot['explore_tickers'] as Map<String, dynamic>;
      final bad = tickers['BAD'] as Map<String, dynamic>;
      expect(bad['fetch_ok'], isFalse);
      expect(bad.containsKey('current_price'), isFalse);
      expect(bad.containsKey('periods'), isFalse);
    });

    test('includes portfolio_fit for held extracted tickers', () async {
      final summary = PortfolioSummary(
        totalValue: 1000,
        totalCostBasis: 900,
        totalPnlAbsolute: 100,
        totalPnlPercent: 11.11,
        valuations: [
          PositionValuation(
            position: Position(
              id: '1',
              ticker: 'AAPL',
              quantity: 2,
              purchasePrice: 100,
              purchaseDate: DateTime(2024, 1, 1),
            ),
            currentPrice: 150,
            marketValue: 300,
            pnlAbsolute: 100,
            pnlPercent: 50,
          ),
          PositionValuation(
            position: Position(
              id: '2',
              ticker: 'MSFT',
              quantity: 1,
              purchasePrice: 200,
              purchaseDate: DateTime(2024, 1, 1),
            ),
            currentPrice: 700,
            marketValue: 700,
            pnlAbsolute: 100,
            pnlPercent: 14.29,
          ),
        ],
      );

      final snapshot = await ExploreContextBuilder.build(
        userMessage: 'AAPL vs NVDA',
        quoteRepository: quoteRepository,
        summary: summary,
        asOf: fixedAsOf,
      );

      final fit = snapshot['portfolio_fit'] as Map<String, dynamic>;
      expect(fit['has_open_positions'], isTrue);
      expect(fit.containsKey('sector_weights'), isFalse);

      final weights = fit['weight_pct'] as Map<String, dynamic>;
      expect(weights['AAPL'], 30.0);
      expect(weights.containsKey('NVDA'), isFalse);
      expect(weights.containsKey('MSFT'), isFalse);
    });

    test('omits portfolio_fit when no open positions', () async {
      final snapshot = await ExploreContextBuilder.build(
        userMessage: 'AAPL',
        quoteRepository: quoteRepository,
        asOf: fixedAsOf,
      );

      expect(snapshot.containsKey('portfolio_fit'), isFalse);
    });

    test('uses SPY proxy for broad market question without ticker', () async {
      final snapshot = await ExploreContextBuilder.build(
        userMessage: '¿Cómo está el mercado?',
        quoteRepository: quoteRepository,
        asOf: fixedAsOf,
      );

      expect(snapshot['market_proxy_ticker'], 'SPY');
      expect(snapshot['market_proxy_label'], isNotEmpty);

      final tickers = snapshot['explore_tickers'] as Map<String, dynamic>;
      expect(tickers.containsKey('SPY'), isTrue);
      expect(tickers.containsKey('C'), isFalse);

      final spy = tickers['SPY'] as Map<String, dynamic>;
      expect(spy['fetch_ok'], isTrue);
      expect(spy['current_price'], _FakeQuoteRepository.spyPrice);
    });

    test('resolves company name via ticker search client', () async {
      final snapshot = await ExploreContextBuilder.build(
        userMessage: 'como le fue a la accion de takes two esta semana',
        quoteRepository: _FakeQuoteRepositoryWithTtwo(),
        asOf: fixedAsOf,
        tickerSearchClient: _FakeTickerSearchClient({
          'takes two': [
            const TickerSearchHit(
              symbol: 'TTWO',
              quoteType: 'EQUITY',
              shortName: 'Take-Two Interactive',
            ),
          ],
        }),
      );

      final tickers = snapshot['explore_tickers'] as Map<String, dynamic>;
      expect(tickers.containsKey('TTWO'), isTrue);
      expect(tickers['TTWO']!['fetch_ok'], isTrue);
    });

    test('includes news_sources when enricher provided for news query', () async {
      final enricher = ExploreNewsEnricher(
        client: _FakeOpenAIRawChatClient(
          onSearchNews: ({required userQuery, required tickers}) async {
            expect(userQuery, '¿qué noticias hay de AAPL?');
            expect(tickers, ['AAPL']);
            return '''
- headline: Apple unveils new product line
- url: https://example.com/aapl-news
- Apple announced a major product refresh today.
''';
          },
        ),
      );

      final snapshot = await ExploreContextBuilder.build(
        userMessage: '¿qué noticias hay de AAPL?',
        quoteRepository: quoteRepository,
        asOf: fixedAsOf,
        newsEnricher: enricher,
      );

      expect(snapshot['news_enrichment'], 'ok');
      final sources = snapshot['news_sources'] as List<dynamic>;
      expect(sources, hasLength(1));
      final source = sources.first as Map<String, dynamic>;
      expect(source['title'], 'Apple unveils new product line');
      expect(source['url'], 'https://example.com/aapl-news');
      expect(source['snippet'], contains('major product refresh'));
    });
  });
}
