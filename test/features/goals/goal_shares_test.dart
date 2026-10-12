import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_progress.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_shares.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';

UserGoal _goal(
  String id, {
  required Set<String> linked,
  Map<String, int> buy = const {},
  GoalStatus status = GoalStatus.active,
}) => UserGoal(
  id: id,
  label: id,
  type: GoalType.purchase,
  targetAmount: 25000,
  targetDate: DateTime(2030, 10, 1),
  snapshot: GoalPlanSnapshot(
    inputs: SavingsPlanInputs(
      targetAmount: 25000,
      months: 48,
      currentAmount: 0,
      risk: RiskTolerance.aggressive,
      startDate: DateTime(2026, 10, 1),
    ),
    buyPlan: [
      for (final e in buy.entries)
        GoalBuyPlanEntry(
          ticker: e.key,
          assetClassLabel: 'Bonos',
          pct: 15,
          monthlyAmount: e.value,
        ),
    ],
  ),
  status: status,
  createdAt: DateTime(2026, 10, 1),
  linkedTickers: linked,
);

void main() {
  // La jubilación pone 103 $/mes en BND y la camioneta 72 $/mes.
  final retirement = _goal(
    'Jubilación',
    linked: const {'SCHD', 'BND'},
    buy: const {'SCHD': 586, 'BND': 103},
  );
  final truck = _goal(
    'Camioneta',
    linked: const {'VT', 'BND'},
    buy: const {'VT': 406, 'BND': 72},
  );
  final goals = [retirement, truck];
  const holdings = {'BND': 1000.0, 'VT': 500.0, 'SCHD': 200.0};

  test('a shared ETF is split by how much each plan puts in it', () {
    expect(GoalShares.shareOf(retirement, 'BND', goals), closeTo(103 / 175, 1e-9));
    expect(GoalShares.shareOf(truck, 'BND', goals), closeTo(72 / 175, 1e-9));
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
      buy: const {'BND': 500},
      status: GoalStatus.achieved,
    );
    final all = [...goals, done];
    expect(GoalShares.shareOf(truck, 'BND', all), closeTo(72 / 175, 1e-9));
    expect(GoalShares.othersCounting(truck, 'BND', all), [retirement]);
  });
}
