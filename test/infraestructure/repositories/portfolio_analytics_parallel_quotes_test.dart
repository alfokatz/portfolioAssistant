// La Home sin caché (recién logueado) quedaba ~10 s en skeleton: las
// cotizaciones se pedían de a una, una por lote. Ahora se piden por ticker
// y varias a la vez.
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/utils/bounded_concurrency.dart';
import 'package:portfolio_assistant/infraestructure/repositories/portfolio_analytics_repository_impl.dart';

class _Positions implements PositionRepository {
  _Positions(this.positions);

  final List<Position> positions;

  @override
  Future<Either<HttpError, List<Position>>> getPositions() async =>
      Right(positions);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Cada pedido tarda 50 ms; registra cuántos hay en vuelo a la vez.
class _SlowQuotes implements QuoteRepository {
  final priceCalls = <String>[];
  final historyCalls = <String>[];
  int inFlight = 0;
  int maxInFlight = 0;

  Future<T> _slow<T>(T value) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    inFlight--;
    return value;
  }

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) {
    priceCalls.add(ticker);
    if (ticker == 'FAIL') {
      return _slow(Left(HttpError(code: 'quote_error', message: 'sin precio')));
    }
    return _slow(Right(ticker == 'AAPL' ? 200.0 : 50.0));
  }

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) {
    historyCalls.add(ticker);
    final today = DateTime.now();
    return _slow(
      Right([
        for (var i = 30; i >= 0; i--)
          PriceCandle(
            date: DateTime(today.year, today.month, today.day - i),
            close: 100,
          ),
      ]),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Position _lot(String id, String ticker, {double price = 10}) => Position(
  id: id,
  ticker: ticker,
  quantity: 1,
  purchasePrice: price,
  purchaseDate: DateTime.now().subtract(const Duration(days: 60)),
);

void main() {
  group('mapWithConcurrency', () {
    test('keeps the order of the input and respects the limit', () async {
      var inFlight = 0;
      var maxInFlight = 0;
      final result = await mapWithConcurrency([5, 1, 4, 2, 3, 6, 7, 8], (
        n,
      ) async {
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        await Future<void>.delayed(Duration(milliseconds: n * 5));
        inFlight--;
        return n * 10;
      }, limit: 3);
      expect(result, [50, 10, 40, 20, 30, 60, 70, 80]);
      expect(maxInFlight, 3);
    });

    test('an empty list returns right away', () async {
      expect(await mapWithConcurrency(<int>[], (n) async => n), isEmpty);
    });
  });

  group('portfolio summary', () {
    test('one quote per ticker (not per lot), several at once', () async {
      final quotes = _SlowQuotes();
      final repo = PortfolioAnalyticsRepositoryImpl(
        positionRepository: _Positions([
          _lot('1', 'AAPL'),
          _lot('2', 'AAPL'),
          _lot('3', 'MSFT'),
          _lot('4', 'KO'),
          _lot('5', 'VOO'),
        ]),
        quoteRepository: quotes,
      );

      final summary = (await repo.getSummary()).getOrElse(
        () => throw StateError('sin resumen'),
      );

      expect(quotes.priceCalls..sort(), ['AAPL', 'KO', 'MSFT', 'VOO']);
      expect(quotes.maxInFlight, 4);
      // Cada ticker con su precio (los dos lotes de AAPL, juntos).
      expect(
        {for (final v in summary.valuations) v.position.ticker: v.currentPrice},
        {'AAPL': 200, 'MSFT': 50, 'KO': 50, 'VOO': 50},
      );
      expect(
        summary.valuations
            .firstWhere((v) => v.position.ticker == 'AAPL')
            .position
            .quantity,
        2,
      );
    });

    test('without a quote, the lot keeps its purchase price', () async {
      final repo = PortfolioAnalyticsRepositoryImpl(
        positionRepository: _Positions([_lot('1', 'FAIL', price: 33)]),
        quoteRepository: _SlowQuotes(),
      );
      final summary = (await repo.getSummary()).getOrElse(
        () => throw StateError('sin resumen'),
      );
      expect(summary.valuations.single.currentPrice, 33);
    });
  });

  test('the chart fetches each ticker once, several at once', () async {
    final quotes = _SlowQuotes();
    final repo = PortfolioAnalyticsRepositoryImpl(
      positionRepository: _Positions([
        _lot('1', 'AAPL'),
        _lot('2', 'AAPL'),
        _lot('3', 'MSFT'),
        _lot('4', 'KO'),
      ]),
      quoteRepository: quotes,
    );

    final history = (await repo.getPortfolioHistory()).getOrElse(() => []);

    expect(history, isNotEmpty);
    expect(quotes.historyCalls..sort(), ['AAPL', 'KO', 'MSFT']);
    expect(quotes.maxInFlight, 3);
  });

  test(
    'the S&P comparison downloads the S&P together with the portfolio',
    () async {
      final quotes = _SlowQuotes();
      final repo = PortfolioAnalyticsRepositoryImpl(
        positionRepository: _Positions([_lot('1', 'AAPL'), _lot('2', 'KO')]),
        quoteRepository: quotes,
      );

      final points = (await repo.getBenchmarkComparison()).getOrElse(() => []);

      expect(points, isNotEmpty);
      expect(quotes.historyCalls..sort(), ['AAPL', 'KO', '^GSPC']);
      expect(quotes.maxInFlight, 3);
    },
  );
}
