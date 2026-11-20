import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/base/base_use_case.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';

class GetPriceOnDateParams {
  final String ticker;
  final DateTime date;

  GetPriceOnDateParams({
    required this.ticker,
    required this.date,
  });
}

class GetPriceOnDateUseCase extends BaseUseCase<double, GetPriceOnDateParams> {
  final QuoteRepository quoteRepository;

  GetPriceOnDateUseCase({required this.quoteRepository});

  @override
  Future<Either<HttpError, double>> call({
    required GetPriceOnDateParams params,
  }) async {
    final result = await quoteRepository.getHistoricalDaily(params.ticker);
    return result.map((candles) => _closeOnOrBefore(candles, params.date));
  }

  double _closeOnOrBefore(List<PriceCandle> candles, DateTime date) {
    if (candles.isEmpty) return 0;
    final target = DateTime(date.year, date.month, date.day);
    PriceCandle? best;
    for (final c in candles) {
      final day = DateTime(c.date.year, c.date.month, c.date.day);
      if (day.isAfter(target)) continue;
      if (best == null || c.date.isAfter(best.date)) best = c;
    }
    // If the purchase date precedes available market data, fall back to first.
    return (best ?? candles.first).close;
  }
}

final getPriceOnDateUseCaseProvider = Provider(
  (ref) => GetPriceOnDateUseCase(
    quoteRepository: ref.watch(quoteRepositoryProvider),
  ),
);

