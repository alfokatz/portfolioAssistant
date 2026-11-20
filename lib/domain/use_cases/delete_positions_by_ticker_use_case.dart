import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/base/base_use_case.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/position_repository_impl.dart';

class DeletePositionsByTickerUseCase extends BaseUseCase<void, String> {
  final PositionRepository repository;

  DeletePositionsByTickerUseCase({required this.repository});

  @override
  Future<Either<HttpError, void>> call({required String params}) {
    return repository.deletePositionsByTicker(params);
  }
}

final deletePositionsByTickerUseCaseProvider = Provider(
  (ref) => DeletePositionsByTickerUseCase(
    repository: ref.watch(positionRepositoryProvider),
  ),
);
