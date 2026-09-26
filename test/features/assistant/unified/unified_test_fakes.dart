import 'package:dartz/dartz.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/entities/earnings_calendar_entry.dart';
import 'package:portfolio_assistant/domain/entities/earnings_report_result.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/entities/symbol_search_result.dart';
import 'package:portfolio_assistant/domain/repositories/company_news_repository.dart';
import 'package:portfolio_assistant/domain/repositories/earnings_calendar_repository.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/repositories/symbol_search_repository.dart';

/// Registra cada ticker pedido a Yahoo, para verificar que el pipeline
/// unificado no pide precios que el mensaje no necesita.
class CountingQuoteRepository implements QuoteRepository {
  CountingQuoteRepository({this.failing = const {}});

  final Set<String> failing;
  final priceCalls = <String>[];
  final dailyCalls = <String>[];

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async {
    priceCalls.add(ticker);
    if (failing.contains(ticker)) return Left(HttpError(code: 'x'));
    return const Right(150);
  }

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) async {
    dailyCalls.add(ticker);
    if (failing.contains(ticker)) return Left(HttpError(code: 'x'));
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

class FakeSymbolSearchRepository implements SymbolSearchRepository {
  FakeSymbolSearchRepository(this.results);

  final Map<String, List<SymbolSearchResult>> results;
  final queries = <String>[];

  @override
  Future<Either<HttpError, List<SymbolSearchResult>>> search(
    String query,
  ) async {
    queries.add(query);
    return Right(results[query] ?? const []);
  }
}

class FakeCompanyNewsRepository implements CompanyNewsRepository {
  final calls = <String>[];

  @override
  Future<Either<HttpError, List<CompanyNewsItem>>> getRecentNews(
    String ticker, {
    int limit = 3,
  }) async {
    calls.add(ticker);
    return Right([
      CompanyNewsItem(
        ticker: ticker,
        headline: '$ticker headline',
        summary: 'summary',
        url: 'https://example.com',
        source: 'Reuters',
        publishedAt: DateTime.utc(2026, 9, 24),
      ),
    ]);
  }
}

class FakeEarningsCalendarRepository implements EarningsCalendarRepository {
  final calls = <String>[];

  @override
  Future<Either<HttpError, EarningsCalendarEntry?>> getNextEarningsDate(
    String ticker,
  ) async {
    calls.add(ticker);
    return const Right(null);
  }

  @override
  Future<Either<HttpError, EarningsReportResult?>> getLatestEarningsResult(
    String ticker,
  ) async => const Right(null);
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

/// Cartera de prueba: AAPL y NVDA en tenencia.
final heldSummary = PortfolioSummary(
  totalValue: 600,
  totalCostBasis: 400,
  totalPnlAbsolute: 200,
  totalPnlPercent: 50,
  valuations: [_valuation('AAPL'), _valuation('NVDA')],
);
