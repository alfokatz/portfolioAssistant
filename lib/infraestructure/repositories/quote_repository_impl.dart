import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/data_sources/quote_remote_data_source.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/yahoo_quote_remote_data_source.dart';

class QuoteRepositoryImpl implements QuoteRepository {
  final QuoteRemoteDataSource remoteDataSource;

  QuoteRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async {
    try {
      final price = await remoteDataSource.getCurrentPrice(ticker);
      return Right(price);
    } catch (e) {
      return Left(
        HttpError(
          code: 'quote_error',
          message: 'No se pudo obtener cotización para $ticker',
        ),
      );
    }
  }

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) async {
    try {
      final candles = await remoteDataSource.getHistoricalDaily(ticker);
      return Right(candles);
    } catch (e) {
      return Left(
        HttpError(
          code: 'history_error',
          message: 'No se pudo obtener histórico para $ticker',
        ),
      );
    }
  }
}

final quoteRepositoryProvider = Provider<QuoteRepository>(
  (ref) => QuoteRepositoryImpl(
    remoteDataSource: ref.watch(quoteRemoteDataSourceProvider),
  ),
);
