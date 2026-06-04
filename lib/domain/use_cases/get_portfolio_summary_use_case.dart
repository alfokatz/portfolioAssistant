import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/base/base_use_case.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/repositories/portfolio_analytics_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/portfolio_analytics_repository_impl.dart';

class GetPortfolioSummaryUseCase extends BaseUseCase<PortfolioSummary, void> {
  final PortfolioAnalyticsRepository repository;

  GetPortfolioSummaryUseCase({required this.repository});

  @override
  Future<Either<HttpError, PortfolioSummary>> call({void params}) {
    return repository.getSummary();
  }
}

final getPortfolioSummaryUseCaseProvider = Provider(
  (ref) => GetPortfolioSummaryUseCase(
    repository: ref.watch(portfolioAnalyticsRepositoryProvider),
  ),
);
