import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/base/base_use_case.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/repositories/closed_position_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/closed_position_repository_impl.dart';

class GetClosedPositionsUseCase
    extends BaseUseCase<List<ClosedPosition>, void> {
  final ClosedPositionRepository repository;

  GetClosedPositionsUseCase({required this.repository});

  @override
  Future<Either<HttpError, List<ClosedPosition>>> call({void params}) {
    return repository.getClosedPositions();
  }
}

final getClosedPositionsUseCaseProvider = Provider(
  (ref) => GetClosedPositionsUseCase(
    repository: ref.watch(closedPositionRepositoryProvider),
  ),
);
