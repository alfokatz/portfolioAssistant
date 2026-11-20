import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';

/// "Me quiero jubilar a los 60 con 1 millón de USD; tengo 24 años": el
/// modelo mandaba `monthly_contribution: 0` sin que el usuario dijera un
/// aporte, y todo el plan (la card, la compra mensual y la meta guardada)
/// quedaba en "0 $/mes".
void main() {
  final asOf = DateTime(2026, 10, 12);

  GoalDraft retirement({double? monthly}) =>
      GoalDraft.fromToolResult(
        GoalProjectionBuilder.build(
          currentPortfolioValue: 0,
          targetAmount: 1000000,
          targetDate: DateTime(2062, 10, 12),
          label: 'Jubilación a los 60 años',
          monthlyContribution: monthly,
          isRetirement: true,
          asOf: asOf,
        ),
      )!;

  test('a 0 monthly contribution is "not stated": the plan uses the '
      'required one', () {
    final zero = retirement(monthly: 0);
    final none = retirement();
    expect(zero.snapshot.inputs.monthlyContribution, isNull);
    expect(zero.snapshot.plan.monthlyUsed, greaterThan(0));
    expect(
      zero.snapshot.plan.monthlyUsed,
      closeTo(none.snapshot.plan.monthlyUsed, 0.01),
    );
  });

  test('a goal already saved with 0 per month heals when it is read', () {
    final inputs = SavingsPlanInputs.fromJson({
      ...retirement().snapshot.inputs.toJson(),
      'monthly_contribution': 0,
    })!;
    expect(inputs.monthlyContribution, isNull);
    expect(SavingsPlan.build(inputs).monthlyUsed, greaterThan(0));
  });

  test('the amount picked with the slider is the one saved, with the buy '
      'plan split the same way', () {
    final draft = retirement().withMonthlyContribution(1000);
    expect(draft.snapshot.inputs.monthlyContribution, 1000);
    expect(draft.snapshot.plan.monthlyUsed, 1000);
    for (final e in draft.snapshot.buyPlan) {
      expect(e.monthlyAmount, (1000 * e.pct / 100).round());
    }
    // Survives the round trip to the database.
    final stored = GoalPlanSnapshot.fromJson(draft.snapshot.toJson())!;
    expect(stored.plan.monthlyUsed, 1000);
    // A different plan from Porty's, so it is not mistaken for it.
    expect(draft.planKey, isNot(retirement().planKey));

    // Slider at 0: nothing changes.
    final same = retirement();
    expect(same.withMonthlyContribution(0), same);
  });
}
