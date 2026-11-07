import 'package:portfolio_assistant/domain/entities/price_candle.dart';

abstract class QuoteRemoteDataSource {
  Future<double> getCurrentPrice(String ticker);

  Future<List<PriceCandle>> getHistoricalDaily(String ticker);

  /// Velas de 5 minutos de la última sesión. Nunca tira: cualquier falla
  /// devuelve una lista vacía (ver la implementación de Yahoo).
  Future<List<PriceCandle>> getIntradayCandles(String ticker);
}
