import 'package:dartz/dartz.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';

abstract class QuoteRepository {
  Future<Either<HttpError, double>> getCurrentPrice(String ticker);

  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  );

  /// Velas de 5 minutos de la última sesión; lista vacía si no hay datos
  /// o la llamada falló (el caller no distingue entre ambos casos).
  Future<List<PriceCandle>> getIntradayCandles(String ticker);
}
