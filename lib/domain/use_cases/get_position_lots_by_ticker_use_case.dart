import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/base/base_use_case.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/infraestructure/repositories/position_repository_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';

class GetPositionLotsByTickerUseCase
    extends BaseUseCase<List<PositionValuation>, String> {
  GetPositionLotsByTickerUseCase({
    required this.positionRepository,
    required this.quoteRepository,
  });

  final PositionRepository positionRepository;
  final QuoteRepository quoteRepository;

  @override
  Future<Either<HttpError, List<PositionValuation>>> call({
    required String params,
  }) async {
    final ticker = PortfolioCalculator.normalizeTicker(params);
    if (ticker.isEmpty) {
      return Left(
        HttpError(code: 'invalid_ticker', message: 'Ticker inválido'),
      );
    }

    final positionsResult = await positionRepository.getPositions();
    return positionsResult.fold(Left.new, (positions) async {
      final lots = positions
          .where(
            (position) =>
                PortfolioCalculator.normalizeTicker(position.ticker) == ticker,
          )
          .toList()
        ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));

      if (lots.isEmpty) {
        return Left(
          HttpError(
            code: 'position_not_found',
            message: 'Posición no encontrada',
          ),
        );
      }

      final priceResult = await quoteRepository.getCurrentPrice(ticker);
      final currentPrice = priceResult.fold(
        (_) => lots.first.purchasePrice,
        (price) => price,
      );

      final valuations = lots
          .map(
            (position) => PortfolioCalculator.valuate(
              position: position,
              currentPrice: currentPrice,
            ),
          )
          .toList();

      return Right(valuations);
    });
  }
}

final getPositionLotsByTickerUseCaseProvider = Provider(
  (ref) => GetPositionLotsByTickerUseCase(
    positionRepository: ref.watch(positionRepositoryProvider),
    quoteRepository: ref.watch(quoteRepositoryProvider),
  ),
);
