import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/base/base_use_case.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_snapshot.dart';
import 'package:portfolio_assistant/domain/repositories/portfolio_analytics_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/portfolio_analytics_repository_impl.dart';

class BuildPortfolioSnapshotUseCase
    extends BaseUseCase<PortfolioSnapshot, void> {
  final PortfolioAnalyticsRepository repository;

  BuildPortfolioSnapshotUseCase({required this.repository});

  @override
  Future<Either<HttpError, PortfolioSnapshot>> call({void params}) {
    return repository.buildSnapshot();
  }
}

final buildPortfolioSnapshotUseCaseProvider = Provider(
  (ref) => BuildPortfolioSnapshotUseCase(
    repository: ref.watch(portfolioAnalyticsRepositoryProvider),
  ),
);
