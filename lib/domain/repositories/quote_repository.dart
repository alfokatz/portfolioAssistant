import 'package:dartz/dartz.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';

abstract class QuoteRepository {
  Future<Either<HttpError, double>> getCurrentPrice(String ticker);

  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  );
}
