import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/base/base_use_case.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/repositories/portfolio_analytics_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/portfolio_analytics_repository_impl.dart';

class ProjectRetirementParams {
  final double targetAmount;
  final int years;
  final double annualContribution;

  ProjectRetirementParams({
    required this.targetAmount,
    required this.years,
    this.annualContribution = 0,
  });
}

class RetirementProjection {
  final double currentValue;
  final double projectedValue;
  final double requiredMonthlyContribution;
  final double assumedAnnualReturn;
  final List<RetirementMilestone> milestones;

  const RetirementProjection({
    required this.currentValue,
    required this.projectedValue,
    required this.requiredMonthlyContribution,
    required this.assumedAnnualReturn,
    required this.milestones,
  });
}

class RetirementMilestone {
  final int year;
  final double projectedValue;
  final String label;

  const RetirementMilestone({
    required this.year,
    required this.projectedValue,
    required this.label,
  });
}

class ProjectRetirementUseCase
    extends BaseUseCase<RetirementProjection, ProjectRetirementParams> {
  final PortfolioAnalyticsRepository repository;
  static const double defaultAnnualReturn = 0.07;

  ProjectRetirementUseCase({required this.repository});

  @override
  Future<Either<HttpError, RetirementProjection>> call({
    required ProjectRetirementParams params,
  }) async {
    final summaryResult = await repository.getSummary();
    return summaryResult.fold(
      Left.new,
      (PortfolioSummary summary) {
        final current = summary.totalValue;
        final rate = defaultAnnualReturn;
        final months = params.years * 12;
        final monthlyRate = rate / 12;

        double projected = current;
        for (var i = 0; i < months; i++) {
          projected = projected * (1 + monthlyRate) + params.annualContribution / 12;
        }

        double requiredMonthly = 0;
        if (projected < params.targetAmount && months > 0) {
          final gap = params.targetAmount - current * _pow(1 + monthlyRate, months);
          if (gap > 0 && monthlyRate > 0) {
            requiredMonthly =
                gap * monthlyRate / (_pow(1 + monthlyRate, months) - 1);
          } else if (gap > 0) {
            requiredMonthly = gap / months;
          }
        }

        final milestones = <RetirementMilestone>[];
        for (var y = 1; y <= params.years; y += params.years > 10 ? 5 : 1) {
          final m = y * 12;
          var val = current;
          for (var i = 0; i < m; i++) {
            val = val * (1 + monthlyRate) + params.annualContribution / 12;
          }
          milestones.add(
            RetirementMilestone(
              year: y,
              projectedValue: val,
              label: 'Año $y',
            ),
          );
        }

        return Right(
          RetirementProjection(
            currentValue: current,
            projectedValue: projected,
            requiredMonthlyContribution: requiredMonthly,
            assumedAnnualReturn: rate * 100,
            milestones: milestones,
          ),
        );
      },
    );
  }

  double _pow(double base, int exp) {
    var result = 1.0;
    for (var i = 0; i < exp; i++) {
      result *= base;
    }
    return result;
  }
}

final projectRetirementUseCaseProvider = Provider(
  (ref) => ProjectRetirementUseCase(
    repository: ref.watch(portfolioAnalyticsRepositoryProvider),
  ),
);
