import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/base/base_use_case.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/repositories/portfolio_analytics_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/portfolio_analytics_repository_impl.dart';

class GetPortfolioHistoryUseCase
    extends BaseUseCase<List<PortfolioHistoryPoint>, void> {
  final PortfolioAnalyticsRepository repository;

  GetPortfolioHistoryUseCase({required this.repository});

  @override
  Future<Either<HttpError, List<PortfolioHistoryPoint>>> call({void params}) {
    return repository.getPortfolioHistory();
  }
}

final getPortfolioHistoryUseCaseProvider = Provider(
  (ref) => GetPortfolioHistoryUseCase(
    repository: ref.watch(portfolioAnalyticsRepositoryProvider),
  ),
);
