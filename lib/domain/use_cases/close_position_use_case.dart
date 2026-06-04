import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/base/base_use_case.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/repositories/closed_position_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/closed_position_repository_impl.dart';

class ClosePositionParams {
  final String ticker;
  final double quantity;
  final double avgPurchasePrice;
  final double closePrice;
  final DateTime closeDate;

  ClosePositionParams({
    required this.ticker,
    required this.quantity,
    required this.avgPurchasePrice,
    required this.closePrice,
    required this.closeDate,
  });
}

class ClosePositionUseCase extends BaseUseCase<ClosedPosition, ClosePositionParams> {
  final ClosedPositionRepository repository;

  ClosePositionUseCase({required this.repository});

  @override
  Future<Either<HttpError, ClosedPosition>> call({
    required ClosePositionParams params,
  }) {
    return repository.closePosition(
      ticker: params.ticker,
      quantity: params.quantity,
      avgPurchasePrice: params.avgPurchasePrice,
      closePrice: params.closePrice,
      closeDate: params.closeDate,
    );
  }
}

final closePositionUseCaseProvider = Provider(
  (ref) => ClosePositionUseCase(
    repository: ref.watch(closedPositionRepositoryProvider),
  ),
);
