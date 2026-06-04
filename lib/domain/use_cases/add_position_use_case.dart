import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/base/base_use_case.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/position_repository_impl.dart';

class AddPositionParams {
  final String ticker;
  final double quantity;
  final double purchasePrice;
  final DateTime purchaseDate;

  AddPositionParams({
    required this.ticker,
    required this.quantity,
    required this.purchasePrice,
    required this.purchaseDate,
  });
}

class AddPositionUseCase extends BaseUseCase<Position, AddPositionParams> {
  final PositionRepository repository;

  AddPositionUseCase({required this.repository});

  @override
  Future<Either<HttpError, Position>> call({required AddPositionParams params}) {
    return repository.addPosition(
      ticker: params.ticker,
      quantity: params.quantity,
      purchasePrice: params.purchasePrice,
      purchaseDate: params.purchaseDate,
    );
  }
}

final addPositionUseCaseProvider = Provider(
  (ref) => AddPositionUseCase(repository: ref.watch(positionRepositoryProvider)),
);
