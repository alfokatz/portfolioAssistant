import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/plan/plan_projection_calculator.dart';

void main() {
  group('PlanProjectionCalculator', () {
    final asOf = DateTime.utc(2026, 6, 10);
    final targetDate = DateTime.utc(2030, 6, 10);

    test('compute calculates required monthly savings and projection', () {
      final projection = PlanProjectionCalculator.compute(
        targetAmount: 50000,
        currentAmount: 12000,
        targetDate: targetDate,
        asOf: asOf,
        monthlyContribution: 200,
      );

      expect(projection.targetAmount, 50000);
      expect(projection.currentAmount, 12000);
      expect(projection.targetDate, targetDate);
      expect(projection.monthsRemaining, 48);
      expect(projection.requiredMonthlySavings, closeTo(791.67, 0.01));
      expect(projection.projectedAmountAtDate, 21600);
      expect(projection.onTrack, isFalse);
      expect(projection.monthlyContribution, 200);
    });

    test('compute marks onTrack when contribution is sufficient', () {
      final projection = PlanProjectionCalculator.compute(
        targetAmount: 20000,
        currentAmount: 10000,
        targetDate: DateTime.utc(2027, 6, 10),
        asOf: asOf,
        monthlyContribution: 1000,
      );

      expect(projection.onTrack, isTrue);
      expect(projection.requiredMonthlySavings, closeTo(833.33, 0.01));
    });

    test('compute enforces minimum one month remaining', () {
      final projection = PlanProjectionCalculator.compute(
        targetAmount: 10000,
        currentAmount: 5000,
        targetDate: DateTime.utc(2026, 6, 15),
        asOf: asOf,
      );

      expect(projection.monthsRemaining, 1);
      expect(projection.requiredMonthlySavings, 5000);
      expect(projection.projectedAmountAtDate, 5000);
    });

    test('milestones returns four linear milestones', () {
      final projection = PlanProjectionCalculator.compute(
        targetAmount: 50000,
        currentAmount: 12000,
        targetDate: targetDate,
        asOf: asOf,
        monthlyContribution: 200,
      );

      final milestones = PlanProjectionCalculator.milestones(
        projection: projection,
        asOf: asOf,
      );

      expect(milestones.length, 4);
      expect(milestones.map((m) => m.label).toList(), ['25%', '50%', '75%', '100%']);
      expect(milestones.first.amount, 12500);
      expect(milestones.last.amount, 50000);
      expect(milestones.last.targetDate, targetDate);
    });
  });
}
