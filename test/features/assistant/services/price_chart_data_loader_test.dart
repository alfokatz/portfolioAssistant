import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/assistant/services/price_chart_data_loader.dart';

class _FakeQuoteRepository implements QuoteRepository {
  _FakeQuoteRepository({this.daily, this.intraday = const []});

  final List<PriceCandle>? daily;
  final List<PriceCandle> intraday;

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async =>
      const Right(1);

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) async =>
      daily == null ? Left(HttpError(code: 'history_error')) : Right(daily!);

  @override
  Future<List<PriceCandle>> getIntradayCandles(String ticker) async => intraday;
}

List<PriceCandle> _dailyCandles(int days) {
  final end = DateTime(2026, 9, 25);
  return [
    for (var i = 0; i < days; i++)
      PriceCandle(
        date: end.subtract(Duration(days: days - 1 - i)),
        close: 100.0 + i,
      ),
  ];
}

void main() {
  group('PriceChartRange.fromWire', () {
    test('maps the model values and defaults to 1M', () {
      expect(PriceChartRange.fromWire('1D'), PriceChartRange.day);
      expect(PriceChartRange.fromWire('ALL'), PriceChartRange.all);
      expect(PriceChartRange.fromWire(null), PriceChartRange.month);
      expect(PriceChartRange.fromWire('weird'), PriceChartRange.month);
    });
  });

  group('PriceChartDataLoader', () {
    test('slices daily history to the range lookback', () async {
      final loader = PriceChartDataLoader(
        _FakeQuoteRepository(daily: _dailyCandles(400)),
      );
      final week = await loader.load('AAPL', PriceChartRange.week);
      expect(week, hasLength(8)); // 7 días hacia atrás + el último, inclusive
      expect(week!.last.close, 499);
      final month = await loader.load('AAPL', PriceChartRange.month);
      expect(month, hasLength(31));
    });

    test(
      'ALL returns the whole history, downsampled keeping both ends',
      () async {
        final loader = PriceChartDataLoader(
          _FakeQuoteRepository(daily: _dailyCandles(2000)),
        );
        final all = await loader.load('AAPL', PriceChartRange.all);
        expect(all, hasLength(PriceChartDataLoader.maxPoints));
        expect(all!.first.close, 100);
        expect(all.last.close, 2099);
      },
    );

    test('1D uses the intraday candles', () async {
      final loader = PriceChartDataLoader(
        _FakeQuoteRepository(
          daily: _dailyCandles(30),
          intraday: [
            PriceCandle(date: DateTime(2026, 9, 25, 10), close: 5),
            PriceCandle(date: DateTime(2026, 9, 25, 10, 5), close: 6),
          ],
        ),
      );
      final day = await loader.load('AAPL', PriceChartRange.day);
      expect(day!.map((c) => c.close), [5, 6]);
    });

    // Un solo camino de fallback: todas estas causas devuelven `null`.
    test(
      'no history, failed history, and failed intraday are all null',
      () async {
        final noHistory = PriceChartDataLoader(_FakeQuoteRepository(daily: []));
        final failedHistory = PriceChartDataLoader(_FakeQuoteRepository());
        final failedIntraday = PriceChartDataLoader(
          _FakeQuoteRepository(daily: _dailyCandles(30)),
        );
        final singlePoint = PriceChartDataLoader(
          _FakeQuoteRepository(daily: _dailyCandles(1)),
        );

        expect(await noHistory.load('X', PriceChartRange.month), isNull);
        expect(await failedHistory.load('X', PriceChartRange.month), isNull);
        expect(await failedIntraday.load('X', PriceChartRange.day), isNull);
        expect(await singlePoint.load('X', PriceChartRange.month), isNull);
      },
    );
  });
}
