import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_progress.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_shares.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';

/// [buy]: ticker → % de la compra mensual. [monthlyAmount] es lo que el
/// plan guardó para cada uno (no decide el reparto).
UserGoal _goal(
  String id, {
  required Set<String> linked,
  Map<String, int> buy = const {},
  double target = 25000,
  double? monthlyContribution,
  int monthlyAmount = 100,
  GoalStatus status = GoalStatus.active,
}) => UserGoal(
  id: id,
  label: id,
  type: GoalType.purchase,
  targetAmount: target,
  targetDate: DateTime(2030, 10, 1),
  snapshot: GoalPlanSnapshot(
    inputs: SavingsPlanInputs(
      targetAmount: target,
      months: 48,
      currentAmount: 0,
      monthlyContribution: monthlyContribution,
      risk: RiskTolerance.aggressive,
      startDate: DateTime(2026, 10, 1),
    ),
    buyPlan: [
      for (final e in buy.entries)
        GoalBuyPlanEntry(
          ticker: e.key,
          assetClassLabel: 'Bonos',
          pct: e.value,
          monthlyAmount: monthlyAmount,
        ),
    ],
  ),
  status: status,
  createdAt: DateTime(2026, 10, 1),
  linkedTickers: linked,
);

void main() {
  // Las dos metas necesitan lo mismo por mes; la jubilación pone el 30 %
  // en BND y la camioneta el 15 %.
  final retirement = _goal(
    'Jubilación',
    linked: const {'SCHD', 'BND'},
    buy: const {'SCHD': 70, 'BND': 30},
  );
  final truck = _goal(
    'Camioneta',
    linked: const {'VT', 'BND'},
    buy: const {'VT': 85, 'BND': 15},
  );
  final goals = [retirement, truck];
  const holdings = {'BND': 1000.0, 'VT': 500.0, 'SCHD': 200.0};

  test('a shared ETF is split by how much each plan needs to put in it', () {
    expect(GoalShares.shareOf(retirement, 'BND', goals), closeTo(30 / 45, 1e-9));
    expect(GoalShares.shareOf(truck, 'BND', goals), closeTo(15 / 45, 1e-9));
    expect(GoalShares.shareOf(truck, 'VT', goals), 1);
    expect(GoalShares.shareOf(truck, 'SCHD', goals), 0);
  });

  test('never counted twice: the shares add up to what the user holds', () {
    final saved = [
      for (final g in goals)
        GoalProgress.of(
          g,
          DateTime(2026, 10, 12),
          holdings: GoalShares.holdingsFor(g, goals, holdings),
        ).saved,
    ];
    expect(saved.reduce((a, b) => a + b), closeTo(1700, 1e-6));
  });

  test('a goal that does not buy it in its plan splits it equally', () {
    final manual = _goal('Viaje', linked: const {'BND'});
    final all = [...goals, manual];
    for (final g in all) {
      expect(GoalShares.shareOf(g, 'BND', all), closeTo(1 / 3, 1e-9));
    }
  });

  test('an achieved goal does not take a share from the active ones', () {
    final done = _goal(
      'Moto',
      linked: const {'BND'},
      buy: const {'BND': 50},
      status: GoalStatus.achieved,
    );
    final all = [...goals, done];
    expect(GoalShares.shareOf(truck, 'BND', all), closeTo(15 / 45, 1e-9));
    expect(GoalShares.othersCounting(truck, 'BND', all), [retirement]);
  });

  test('a contribution typed in another currency does not take the whole '
      'holding: it splits by what each plan needs', () {
    // Japón: 18.000 en el mismo plazo. Fiesta: 5.000, guardada con 20.000
    // "por mes" (eran pesos) y por eso 14.000 $/mes en SGOV.
    final japan = _goal(
      'Japón',
      linked: const {'SGOV'},
      buy: const {'SGOV': 70},
      target: 18000,
      monthlyAmount: 628,
    );
    final party = _goal(
      'Fiesta',
      linked: const {'SGOV'},
      buy: const {'SGOV': 70},
      target: 5000,
      monthlyContribution: 20000,
      monthlyAmount: 14000,
    );
    final both = [japan, party];
    // Mismo plazo y mismo %: la parte sigue al monto de cada meta.
    expect(GoalShares.shareOf(japan, 'SGOV', both), closeTo(18 / 23, 0.01));
    expect(GoalShares.shareOf(party, 'SGOV', both), closeTo(5 / 23, 0.01));
  });
}
