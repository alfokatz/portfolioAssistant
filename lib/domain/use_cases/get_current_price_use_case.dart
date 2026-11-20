import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/base/base_use_case.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';

class GetCurrentPriceUseCase extends BaseUseCase<double, String> {
  final QuoteRepository quoteRepository;

  GetCurrentPriceUseCase({required this.quoteRepository});

  @override
  Future<Either<HttpError, double>> call({required String params}) {
    return quoteRepository.getCurrentPrice(params);
  }
}

final getCurrentPriceUseCaseProvider = Provider(
  (ref) => GetCurrentPriceUseCase(
    quoteRepository: ref.watch(quoteRepositoryProvider),
  ),
);

