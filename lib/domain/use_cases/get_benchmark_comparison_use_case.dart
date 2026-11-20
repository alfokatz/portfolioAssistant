import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/base/base_use_case.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/benchmark_point.dart';
import 'package:portfolio_assistant/domain/repositories/portfolio_analytics_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/portfolio_analytics_repository_impl.dart';

class GetBenchmarkComparisonUseCase
    extends BaseUseCase<List<BenchmarkPoint>, void> {
  final PortfolioAnalyticsRepository repository;

  GetBenchmarkComparisonUseCase({required this.repository});

  @override
  Future<Either<HttpError, List<BenchmarkPoint>>> call({void params}) {
    return repository.getBenchmarkComparison();
  }
}

final getBenchmarkComparisonUseCaseProvider = Provider(
  (ref) => GetBenchmarkComparisonUseCase(
    repository: ref.watch(portfolioAnalyticsRepositoryProvider),
  ),
);
