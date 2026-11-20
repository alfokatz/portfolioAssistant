import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/use_cases/get_current_price_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_price_on_date_use_case.dart';
import 'package:portfolio_assistant/presentation/flows/position/providers/add_position_provider.dart';
import 'package:portfolio_assistant/presentation/flows/position/states/add_position_state.dart';

class _Quotes implements QuoteRepository {
  var current = 717.23;

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String t) async =>
      Right(current);
  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String t,
  ) async => Right([PriceCandle(date: DateTime(2024, 3, 22), close: 479.18)]);
  @override
  Future<List<PriceCandle>> getIntradayCandles(String t) async => [];
}

AddPositionProvider _provider(
  _Quotes quotes, {
  AddPositionArgs args = const AddPositionArgs(),
}) => AddPositionProvider(
  args: args,
  getPriceOnDateUseCase: GetPriceOnDateUseCase(quoteRepository: quotes),
  getCurrentPriceUseCase: GetCurrentPriceUseCase(quoteRepository: quotes),
);

void main() {
  test('with today\'s date, the purchase price is the current one', () async {
    final p = _provider(_Quotes())..setTickerText('VOO');
    await p.fetchCurrentPrice();
    expect(p.state.priceText, '717.23');
  });

  test('changing the ticker updates the autofilled price', () async {
    final quotes = _Quotes();
    final p = _provider(quotes)..setTickerText('VOO');
    await p.fetchCurrentPrice();
    quotes.current = 250.5;
    p.setTickerText('AAPL');
    await p.fetchCurrentPrice();
    expect(p.state.priceText, '250.50');
  });

  test('a price typed by the user is never overwritten', () async {
    final p = _provider(_Quotes())..setTickerText('VOO');
    p.setPriceText('700');
    await p.fetchCurrentPrice();
    expect(p.state.priceText, '700');
  });

  test('with another date, the price is that day\'s close', () async {
    final p = _provider(_Quotes())..setTickerText('VOO');
    await p.setPurchaseDate(DateTime(2024, 3, 22));
    expect(p.state.priceText, '479.18');
  });

  test('a prefilled price (from Porty) is kept', () async {
    final p = _provider(
      _Quotes(),
      args: const AddPositionArgs(prefilledTicker: 'VOO', prefilledPrice: 600),
    );
    await p.fetchCurrentPrice();
    expect(p.state.priceText, '600.0');
  });
}
