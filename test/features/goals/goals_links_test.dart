import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/goals/data/goals_repository.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';

/// Repo en memoria: lo justo para ver qué inversiones se asignan.
class _Repo extends GoalsRepository {
  _Repo() : super(client: () => null);

  final goals = <UserGoal>[];

  @override
  Future<List<UserGoal>> list() async => [...goals];

  @override
  Future<UserGoal> create(
    GoalDraft draft, {
    Set<String> linkedTickers = const {},
  }) async {
    final goal = UserGoal(
      id: 'g${goals.length}',
      label: draft.label,
      type: draft.type,
      targetAmount: draft.targetAmount,
      targetDate: draft.targetDate,
      snapshot: draft.snapshot,
      status: GoalStatus.active,
      createdAt: DateTime(2026, 10, 11),
      linkedTickers: linkedTickers,
    );
    goals.add(goal);
    return goal;
  }

  @override
  Future<void> updatePlan(
    String id,
    GoalDraft draft, {
    Set<String>? linkedTickers,
  }) async {
    if (linkedTickers != null) await setLinkedTickers(id, linkedTickers);
  }

  @override
  Future<void> setLinkedTickers(String id, Set<String> tickers) async {
    final i = goals.indexWhere((g) => g.id == id);
    final g = goals[i];
    goals[i] = UserGoal(
      id: g.id,
      label: g.label,
      type: g.type,
      targetAmount: g.targetAmount,
      targetDate: g.targetDate,
      snapshot: g.snapshot,
      status: g.status,
      createdAt: g.createdAt,
      linkedTickers: tickers,
    );
  }
}

GoalDraft _draft(String label, GoalType type, List<String> buy) => GoalDraft(
  label: label,
  type: type,
  targetAmount: 1000,
  targetDate: DateTime(2027, 10, 1),
  snapshot: GoalPlanSnapshot(
    inputs: SavingsPlanInputs(
      targetAmount: 1000,
      months: 12,
      currentAmount: 0,
      risk: RiskTolerance.moderate,
      startDate: DateTime(2026, 10, 1),
    ),
    buyPlan: [
      for (final t in buy)
        GoalBuyPlanEntry(
          ticker: t,
          assetClassLabel: 'Liquidez',
          pct: 50,
          monthlyAmount: 50,
        ),
    ],
  ),
);

void main() {
  test('a saved goal counts its plan instruments right away, without '
      'stealing them from another goal', () async {
    final repo = _Repo();
    final goals = GoalsNotifier(repo, heldTickers: () => {'AAPL', 'BIL'});
    final mac = await goals.save(
      _draft('MacBook', GoalType.purchase, ['BIL', 'SHV']),
    );
    expect(mac.linkedTickers, {'BIL', 'SHV'});

    final trip = await goals.save(
      _draft('Viaje', GoalType.purchase, ['BIL', 'SGOV']),
    );
    expect(trip.linkedTickers, {'SGOV'});

    // Una jubilación parte del valor de la cartera: cuenta lo que queda.
    final retirement = await goals.save(_draft('Jubilación', GoalType.retirement, []));
    expect(retirement.linkedTickers, {'AAPL'});
  });

  test('saving a plan for a goal with the same name updates it instead of '
      'duplicating it', () async {
    final repo = _Repo();
    final goals = GoalsNotifier(repo);
    final first = await goals.save(_draft('MacBook', GoalType.purchase, ['BIL']));
    final again = await goals.save(_draft('macbook ', GoalType.purchase, ['SGOV']));
    expect(again.id, first.id);
    expect(goals.state.goals, hasLength(1));
    expect(again.linkedTickers, {'BIL', 'SGOV'});
  });

  test('assigning a ticker to a goal moves it out of the other one', () async {
    final repo = _Repo();
    final goals = GoalsNotifier(repo);
    final mac = await goals.save(_draft('MacBook', GoalType.purchase, ['BIL']));
    final trip = await goals.save(_draft('Viaje', GoalType.purchase, ['SGOV']));

    await goals.setLinkedTickers(trip.id, {'SGOV', 'bil'});

    expect(goals.state.byId(trip.id)!.linkedTickers, {'SGOV', 'BIL'});
    expect(goals.state.byId(mac.id)!.linkedTickers, isEmpty);
  });
}
