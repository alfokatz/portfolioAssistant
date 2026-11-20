import 'package:dartz/dartz.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/benchmark_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_snapshot.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';

abstract class PortfolioAnalyticsRepository {
  Future<Either<HttpError, PortfolioSummary>> getSummary();

  Future<Either<HttpError, List<PortfolioHistoryPoint>>> getPortfolioHistory();

  Future<Either<HttpError, List<BenchmarkPoint>>> getBenchmarkComparison();

  Future<Either<HttpError, PortfolioSnapshot>> buildSnapshot();
}
