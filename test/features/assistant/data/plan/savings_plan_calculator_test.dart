import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';

SavingsPlanInputs _inputs({
  double target = 500000,
  int months = 240,
  double current = 0,
  RiskTolerance risk = RiskTolerance.moderate,
  double? monthly,
  bool retirement = false,
}) => SavingsPlanInputs(
  targetAmount: target,
  months: months,
  currentAmount: current,
  risk: risk,
  startDate: DateTime(2026, 10, 9),
  monthlyContribution: monthly,
  isRetirement: retirement,
);

void main() {
  group('SavingsPlanCalculator', () {
    test('with no return the math is linear', () {
      expect(
        SavingsPlanCalculator.requiredMonthly(
          target: 12000,
          current: 0,
          months: 12,
          annualReturn: 0,
        ),
        1000,
      );
      expect(
        SavingsPlanCalculator.futureValue(
          current: 100,
          monthly: 10,
          months: 5,
          annualReturn: 0,
        ),
        150,
      );
    });

    test('required monthly and future value are inverses', () {
      final monthly = SavingsPlanCalculator.requiredMonthly(
        target: 500000,
        current: 20000,
        months: 240,
        annualReturn: 0.05,
      );
      final fv = SavingsPlanCalculator.futureValue(
        current: 20000,
        monthly: monthly,
        months: 240,
        annualReturn: 0.05,
      );
      expect(fv, closeTo(500000, 0.01));
    });

    test('the monthly rate compounds to the annual one', () {
      final r = SavingsPlanCalculator.monthlyRate(0.05);
      expect(
        SavingsPlanCalculator.futureValue(
          current: 1,
          monthly: 0,
          months: 12,
          annualReturn: 0.05,
        ),
        closeTo(1.05, 1e-9),
      );
      expect(r, lessThan(0.05 / 12));
    });

    test('capital already enough → nothing to save', () {
      expect(
        SavingsPlanCalculator.requiredMonthly(
          target: 1000,
          current: 900,
          months: 120,
          annualReturn: 0.05,
        ),
        0,
      );
    });

    test('4% rule: income ↔ capital, and how long it lasts', () {
      expect(SavingsPlanCalculator.capitalForIncome(3000), 900000);
      expect(SavingsPlanCalculator.sustainableMonthlyIncome(900000), 3000);
      // Retirando 4% con 2.4% real: dura décadas, pero se agota.
      final months = SavingsPlanCalculator.monthsCapitalLasts(
        capital: 900000,
        monthlyWithdrawal: 3000,
        annualReturn: 0.024,
      );
      expect(months! ~/ 12, inInclusiveRange(35, 45));
      // Si el rendimiento cubre el retiro, no se agota.
      expect(
        SavingsPlanCalculator.monthsCapitalLasts(
          capital: 900000,
          monthlyWithdrawal: 1000,
          annualReturn: 0.024,
        ),
        isNull,
      );
    });
  });

  group('SavingsPlan', () {
    test('the 500k in 20 years case: interest does a big part', () {
      final plan = SavingsPlan.build(_inputs());
      final base = plan.requiredMonthly[PlanScenario.base]!;

      // Lineal serían $2.083/mes; invirtiendo, bastante menos.
      expect(plan.requiredMonthlyNoReturn, closeTo(2083.33, 0.01));
      expect(base, lessThan(plan.requiredMonthlyNoReturn * 0.75));
      expect(plan.projectedBase, closeTo(500000, 0.5));
      expect(plan.growth, greaterThan(100000));
      expect(plan.onTrack, isTrue);
    });

    test('scenarios are ordered: a bad market needs more savings', () {
      final plan = SavingsPlan.build(_inputs());
      final r = plan.requiredMonthly;
      expect(r[PlanScenario.pessimistic]!, greaterThan(r[PlanScenario.base]!));
      expect(r[PlanScenario.base]!, greaterThan(r[PlanScenario.optimistic]!));
    });

    test('more risk → higher expected return → less to save', () {
      double base(RiskTolerance risk) =>
          SavingsPlan.build(_inputs(risk: risk)).requiredMonthly[PlanScenario
              .base]!;
      expect(
        base(RiskTolerance.conservative),
        greaterThan(base(RiskTolerance.moderate)),
      );
      expect(
        base(RiskTolerance.moderate),
        greaterThan(base(RiskTolerance.aggressive)),
      );
    });

    test('allocations add up to 100%', () {
      for (final risk in RiskTolerance.values) {
        final total = PlanAssumptions.allocationFor(
          risk,
        ).values.fold<double>(0, (a, b) => a + b);
        expect(total, closeTo(1, 1e-9), reason: risk.name);
      }
    });

    test('a stated contribution that falls short is not on track', () {
      final plan = SavingsPlan.build(_inputs(monthly: 500));
      expect(plan.monthlyUsed, 500);
      expect(plan.onTrack, isFalse);
      expect(plan.contributed, 500 * 240);
    });

    test('the curve has a point per year plus the exact end', () {
      final plan = SavingsPlan.build(_inputs(months: 30));
      final curve = plan.curve();
      expect(curve.map((p) => p.month), [0, 12, 24, 30]);
      expect(curve.first.base, 0);
      expect(curve.last.base, closeTo(plan.projectedBase, 0.01));
      // La curva con otro aporte (el slider) se mueve.
      expect(
        plan.curve(monthly: plan.monthlyUsed * 2).last.base,
        greaterThan(curve.last.base),
      );
    });

    test('what-ifs: sooner costs more per month, later less', () {
      final plan = SavingsPlan.build(_inputs());
      final sooner = plan.sensitivities.firstWhere((s) => s.key == 'sooner');
      final later = plan.sensitivities.firstWhere((s) => s.key == 'later');
      final base = plan.requiredMonthly[PlanScenario.base]!;
      expect(sooner.requiredMonthly, greaterThan(base));
      expect(later.requiredMonthly, lessThan(base));
    });

    test('retirement adds the two ways to collect an income', () {
      expect(SavingsPlan.build(_inputs()).income, isNull);
      final income = SavingsPlan.build(_inputs(retirement: true)).income!;
      // Sin ingreso pedido: cuánto da la meta por cada camino.
      expect(income.withdrawalMonthly, closeTo(500000 * 0.04 / 12, 1e-6));
      expect(income.dividendsMonthly, closeTo(500000 * 0.035 / 12, 1e-6));
      expect(income.withdrawalYears, isNotNull);
      expect(income.desiredMonthly, isNull);
    });

    test('an income goal: capital per way, dividends need more', () {
      final income =
          SavingsPlan.build(
            SavingsPlanInputs(
              targetAmount: 3000 * 12 / 0.035,
              months: 300,
              currentAmount: 0,
              risk: RiskTolerance.moderate,
              startDate: DateTime(2026, 10, 9),
              isRetirement: true,
              desiredMonthlyIncome: 3000,
            ),
          ).income!;
      expect(income.desiredMonthly, 3000);
      expect(income.strategy, IncomeStrategy.dividends);
      expect(income.withdrawalCapital, 900000);
      expect(income.dividendsCapital, greaterThan(income.withdrawalCapital));
      expect(income.withdrawalYears, inInclusiveRange(30, 45));
    });

    test('the target in future dollars includes inflation', () {
      final plan = SavingsPlan.build(_inputs());
      expect(plan.nominalTarget, greaterThan(800000));
    });

    test('inputs survive the tool result round trip', () {
      final inputs = _inputs(current: 1234.5, monthly: 300, retirement: true);
      final json = SavingsPlan.build(inputs).toToolResult()['inputs'];
      final back = SavingsPlanInputs.fromJson(json)!;
      expect(back.toJson(), inputs.toJson());
    });
  });

  group('GoalProjectionBuilder', () {
    final now = DateTime(2026, 10, 9);

    test('same request → same plan id; different → different', () {
      Map<String, Object?> build(double target) => GoalProjectionBuilder.build(
        currentPortfolioValue: 1000,
        targetAmount: target,
        targetDate: DateTime(2046, 10, 9),
        asOf: now,
      );
      expect(build(500000)['plan_id'], build(500000)['plan_id']);
      expect(build(500000)['plan_id'], isNot(build(600000)['plan_id']));
    });

    test('stated savings replace the portfolio value as starting capital', () {
      final result = GoalProjectionBuilder.build(
        currentPortfolioValue: 1000,
        currentSavings: 50000,
        targetAmount: 500000,
        targetDate: DateTime(2046, 10, 9),
        asOf: now,
      );
      expect(result['starting_capital'], 50000);
      expect(result['starting_capital_source'], 'stated');
    });

    test('a retirement label turns on the income phase', () {
      final result = GoalProjectionBuilder.build(
        currentPortfolioValue: 0,
        label: 'Jubilación',
        targetAmount: 500000,
        targetDate: DateTime(2046, 10, 9),
        asOf: now,
      );
      expect((result['plan'] as Map)['income'], isA<Map>());
    });
  });
}
