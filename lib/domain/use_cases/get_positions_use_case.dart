import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/base/base_use_case.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/position_repository_impl.dart';

class GetPositionsUseCase extends BaseUseCase<List<Position>, void> {
  final PositionRepository repository;

  GetPositionsUseCase({required this.repository});

  @override
  Future<Either<HttpError, List<Position>>> call({void params}) {
    return repository.getPositions();
  }
}

final getPositionsUseCaseProvider = Provider(
  (ref) => GetPositionsUseCase(repository: ref.watch(positionRepositoryProvider)),
);
