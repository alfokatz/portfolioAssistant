import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/entities/earnings_calendar_entry.dart';
import 'package:portfolio_assistant/domain/entities/earnings_report_result.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/company_news_repository.dart';
import 'package:portfolio_assistant/domain/repositories/earnings_calendar_repository.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_context_builder.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_earnings_enricher.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_news_enricher.dart';

class _FakeCompanyNewsRepository implements CompanyNewsRepository {
  _FakeCompanyNewsRepository(this.onGetRecentNews);

  final Future<Either<HttpError, List<CompanyNewsItem>>> Function(
    String ticker,
  )
  onGetRecentNews;

  @override
  Future<Either<HttpError, List<CompanyNewsItem>>> getRecentNews(
    String ticker, {
    int limit = 3,
  }) {
    return onGetRecentNews(ticker);
  }
}

class _FakeEarningsCalendarRepository implements EarningsCalendarRepository {
  _FakeEarningsCalendarRepository({this.nextEntry, this.latestResult});

  final EarningsCalendarEntry? nextEntry;
  final EarningsReportResult? latestResult;

  @override
  Future<Either<HttpError, EarningsCalendarEntry?>> getNextEarningsDate(
    String ticker,
  ) async => Right(nextEntry);

  @override
  Future<Either<HttpError, EarningsReportResult?>> getLatestEarningsResult(
    String ticker,
  ) async => Right(latestResult);
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
      // Mismos períodos que ya computa PortfolioContextBuilder — el
      // historial que trae getHistoricalDaily no está limitado a 30 días,
      // así que Explore también puede responder "últimos 3 meses"/"último
      // año" sin ningún fetch adicional.
      expect(periods.containsKey('quarter'), isTrue);
      expect(periods.containsKey('year'), isTrue);

      final day = periods['day'] as Map<String, dynamic>;
      expect(day['label_es'], 'último día');
      expect(day['has_sufficient_history'], isTrue);
      expect(day.containsKey('change_pct'), isTrue);
      expect(day.containsKey('price_start'), isTrue);
      expect(day.containsKey('price_end'), isTrue);

      final quarter = periods['quarter'] as Map<String, dynamic>;
      expect(quarter['label_es'], 'últimos 90 días');
      final year = periods['year'] as Map<String, dynamic>;
      expect(year['label_es'], 'último año');
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

    test('includes news_sources when enricher provided for news query', () async {
      final enricher = ExploreNewsEnricher(
        newsRepository: _FakeCompanyNewsRepository((ticker) async {
          expect(ticker, 'AAPL');
          return Right([
            CompanyNewsItem(
              ticker: 'AAPL',
              headline: 'Apple unveils new product line',
              summary: 'Apple announced a major product refresh today.',
              url: 'https://example.com/aapl-news',
              source: 'Example Wire',
              publishedAt: fixedAsOf,
            ),
          ]);
        }),
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

    group('earnings_calendar enrichment', () {
      test('adds next_report and latest_result when repository has data', () async {
        final enricher = ExploreEarningsEnricher(
          earningsRepository: _FakeEarningsCalendarRepository(
            nextEntry: EarningsCalendarEntry(
              ticker: 'AAPL',
              reportDate: DateTime(2026, 11, 13),
              fiscalQuarter: 4,
              fiscalYear: 2026,
            ),
            latestResult: EarningsReportResult(
              ticker: 'AAPL',
              reportDate: DateTime(2026, 7, 24),
              epsActual: 1.5,
              epsEstimate: 1.4,
            ),
          ),
        );

        final snapshot = await ExploreContextBuilder.build(
          userMessage: '¿cuándo reporta resultados AAPL?',
          quoteRepository: quoteRepository,
          asOf: fixedAsOf,
          earningsEnricher: enricher,
        );

        expect(snapshot['earnings_calendar_status'], 'ok');
        final calendar =
            snapshot['earnings_calendar'] as Map<String, dynamic>;
        final aapl = calendar['AAPL'] as Map<String, dynamic>;
        final nextReport = aapl['next_report'] as Map<String, dynamic>;
        expect(nextReport['date_label'], '13 nov 2026');
        expect(nextReport['fiscal_period_label'], 'T4 FY26');
        final latestResult = aapl['latest_result'] as Map<String, dynamic>;
        expect(latestResult['eps_actual'], 1.5);
        expect(latestResult['eps_estimate'], 1.4);
        expect(latestResult['beat'], isTrue);
      });

      // Fallback honesto: la API respondió bien pero no hay ningún dato de
      // calendario para el ticker consultado.
      test(
        'marks status empty when repository has no data for the ticker',
        () async {
          final enricher = ExploreEarningsEnricher(
            earningsRepository: _FakeEarningsCalendarRepository(),
          );

          final snapshot = await ExploreContextBuilder.build(
            userMessage: '¿cuándo reporta resultados AAPL?',
            quoteRepository: quoteRepository,
            asOf: fixedAsOf,
            earningsEnricher: enricher,
          );

          expect(snapshot['earnings_calendar_status'], 'empty');
          expect(snapshot['earnings_calendar'], isEmpty);
        },
      );
    });
  });
}
