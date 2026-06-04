import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/benchmark_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_snapshot.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/portfolio_analytics_repository.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/infraestructure/repositories/position_repository_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';

const _sp500Ticker = '^GSPC';

class PortfolioAnalyticsRepositoryImpl implements PortfolioAnalyticsRepository {
  final PositionRepository positionRepository;
  final QuoteRepository quoteRepository;

  PortfolioAnalyticsRepositoryImpl({
    required this.positionRepository,
    required this.quoteRepository,
  });

  Future<Either<HttpError, List<PositionValuation>>> _loadValuations() async {
    final positionsResult = await positionRepository.getPositions();
    return positionsResult.fold(
      Left.new,
      (positions) async {
        if (positions.isEmpty) {
          return const Right([]);
        }
        final valuations = <PositionValuation>[];
        for (final position in positions) {
          final priceResult =
              await quoteRepository.getCurrentPrice(position.ticker);
          final price = priceResult.fold(
            (_) => position.purchasePrice,
            (p) => p,
          );
          valuations.add(
            PortfolioCalculator.valuate(
              position: position,
              currentPrice: price,
            ),
          );
        }
        return Right(valuations);
      },
    );
  }

  @override
  Future<Either<HttpError, PortfolioSnapshot>> buildSnapshot() async {
    final summaryResult = await getSummary();
    return summaryResult.fold(
      Left.new,
      (summary) {
        final total = summary.totalValue;
        final positions = summary.valuations.map((v) {
          final weight = total > 0 ? v.marketValue / total : 0.0;
          return PortfolioSnapshotPosition(
            ticker: v.position.ticker,
            quantity: v.position.quantity,
            purchasePrice: v.position.purchasePrice,
            currentPrice: v.currentPrice,
            marketValue: v.marketValue,
            weight: weight,
            pnlPercent: v.pnlPercent,
            pnlAbsolute: v.pnlAbsolute,
          );
        }).toList();

        return Right(
          PortfolioSnapshot(
            totalValue: summary.totalValue,
            totalPnlPercent: summary.totalPnlPercent,
            totalPnlAbsolute: summary.totalPnlAbsolute,
            asOf: DateTime.now(),
            positions: positions,
          ),
        );
      },
    );
  }

  @override
  Future<Either<HttpError, List<BenchmarkPoint>>> getBenchmarkComparison() async {
    try {
      final positionsResult = await positionRepository.getPositions();
      return await positionsResult.fold(
        Left.new,
        (positions) async {
          if (positions.isEmpty) return const Right([]);

          final startDate = positions
              .map((p) => p.purchaseDate)
              .reduce((a, b) => a.isBefore(b) ? a : b);

          final portfolioHistory = await _buildPortfolioSeries(positions);
          final spResult = await quoteRepository.getHistoricalDaily(_sp500Ticker);
          return spResult.fold(
            Left.new,
            (spCandles) {
              final spFiltered = spCandles
                  .where((c) => !c.date.isBefore(startDate))
                  .toList();
              if (portfolioHistory.isEmpty || spFiltered.isEmpty) {
                return const Right([]);
              }

              final portfolioByDay = {
                for (final p in portfolioHistory)
                  _dayKey(p.date): p.totalValue,
              };
              final spByDay = {
                for (final c in spFiltered) _dayKey(c.date): c.close,
              };

              final commonDays = portfolioByDay.keys
                  .where(spByDay.containsKey)
                  .toList()
                ..sort();

              if (commonDays.isEmpty) return const Right([]);

              final firstDay = commonDays.first;
              final basePortfolio = portfolioByDay[firstDay]!;
              final baseSp = spByDay[firstDay]!;

              final points = commonDays.map((day) {
                final date = DateTime.parse(day);
                final pVal = portfolioByDay[day]!;
                final spVal = spByDay[day]!;
                return BenchmarkPoint(
                  date: date,
                  portfolioNormalized:
                      basePortfolio > 0 ? (pVal / basePortfolio) * 100 : 100,
                  sp500Normalized:
                      baseSp > 0 ? (spVal / baseSp) * 100 : 100,
                );
              }).toList();

              return Right(points);
            },
          );
        },
      );
    } catch (e) {
      return Left(
        HttpError(code: 'analytics_error', message: e.toString()),
      );
    }
  }

  @override
  Future<Either<HttpError, List<PortfolioHistoryPoint>>>
      getPortfolioHistory() async {
    try {
      final positionsResult = await positionRepository.getPositions();
      return await positionsResult.fold(
        Left.new,
        (positions) async {
          if (positions.isEmpty) return const Right([]);
          final series = await _buildPortfolioSeries(positions);
          return Right(series);
        },
      );
    } catch (e) {
      return Left(
        HttpError(code: 'analytics_error', message: e.toString()),
      );
    }
  }

  Future<List<PortfolioHistoryPoint>> _buildPortfolioSeries(
    List<Position> positions,
  ) async {
    final histories = <String, List<PriceCandle>>{};

    for (final position in positions) {
      final ticker = position.ticker;
      if (histories.containsKey(ticker)) continue;
      final result = await quoteRepository.getHistoricalDaily(ticker);
      result.fold(
        (_) => histories[ticker] = [],
        (candles) => histories[ticker] = candles,
      );
    }

    final startDate = positions
        .map((p) => p.purchaseDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);

    final allDates = <DateTime>{};
    for (final candles in histories.values) {
      for (final c in candles) {
        if (!c.date.isBefore(startDate)) {
          allDates.add(DateTime(c.date.year, c.date.month, c.date.day));
        }
      }
    }

    final sortedDates = allDates.toList()..sort();

    final points = <PortfolioHistoryPoint>[];
    for (final date in sortedDates) {
      double total = 0;
      for (final position in positions) {
        if (position.purchaseDate.isAfter(date)) continue;
        final candles = histories[position.ticker] ?? [];
        final price = _closeOnOrBefore(candles, date) ?? position.purchasePrice;
        total += position.quantity * price;
      }
      if (total > 0) {
        points.add(PortfolioHistoryPoint(date: date, totalValue: total));
      }
    }
    return points;
  }

  double? _closeOnOrBefore(List<PriceCandle> candles, DateTime date) {
    PriceCandle? best;
    for (final c in candles) {
      if (c.date.isAfter(date)) continue;
      if (best == null || c.date.isAfter(best.date)) {
        best = c;
      }
    }
    return best?.close;
  }

  String _dayKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  Future<Either<HttpError, PortfolioSummary>> getSummary() async {
    final valuationsResult = await _loadValuations();
    return valuationsResult.fold(
      Left.new,
      (valuations) => Right(PortfolioCalculator.summarize(valuations)),
    );
  }
}

final portfolioAnalyticsRepositoryProvider =
    Provider<PortfolioAnalyticsRepository>(
  (ref) => PortfolioAnalyticsRepositoryImpl(
    positionRepository: ref.watch(positionRepositoryProvider),
    quoteRepository: ref.watch(quoteRepositoryProvider),
  ),
);
