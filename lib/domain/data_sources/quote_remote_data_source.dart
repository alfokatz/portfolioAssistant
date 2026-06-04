import 'package:portfolio_assistant/domain/entities/price_candle.dart';

abstract class QuoteRemoteDataSource {
  Future<double> getCurrentPrice(String ticker);

  Future<List<PriceCandle>> getHistoricalDaily(String ticker);
}
