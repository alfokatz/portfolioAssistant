import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/assistant/tools/advice_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/portfolio_tools.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_progress.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';

import '../assistant/fakes/assistant_fakes.dart';

/// Una meta de 1.200 en 12 meses, empezando de cero el 1/1/2026.
UserGoal _goal({
  Set<String> linked = const {'BIL', 'SHV'},
  double outside = 0,
  GoalStatus status = GoalStatus.active,
}) {
  final inputs = SavingsPlanInputs(
    targetAmount: 1200,
    months: 12,
    currentAmount: 0,
    risk: RiskTolerance.moderate,
    startDate: DateTime(2026, 1, 1),
    shortTerm: true,
  );
  return UserGoal(
    id: 'goal-1',
    label: 'MacBook',
    type: GoalType.purchase,
    targetAmount: 1200,
    targetDate: DateTime(2027, 1, 1),
    snapshot: GoalPlanSnapshot(inputs: inputs),
    status: status,
    createdAt: DateTime(2026, 1, 1),
    linkedTickers: linked,
    externalSavings: outside,
  );
}

void main() {
  group('GoalProgress', () {
    test('just saved: just started', () {
      final p = GoalProgress.of(_goal(), DateTime(2026, 1, 10));
      expect(p.status, GoalProgressStatus.justStarted);
      expect(p.monthsRemaining, 12);
      expect(p.plannedMonthly, greaterThan(90));
    });

    test('what the plan expected by now, from the holdings: on track', () {
      final p0 = GoalProgress.of(_goal(), DateTime(2026, 7, 2));
      final p = GoalProgress.of(
        _goal(),
        DateTime(2026, 7, 2),
        holdings: {'BIL': p0.expected * 0.7, 'SHV': p0.expected * 0.3},
      );
      expect(p.monthsElapsed, 6);
      expect(p.status, GoalProgressStatus.onTrack);
      expect(p.linkedValues.keys, unorderedEquals(['BIL', 'SHV']));
    });

    test('holdings that do not count for the goal are ignored', () {
      final p = GoalProgress.of(
        _goal(),
        DateTime(2026, 7, 2),
        holdings: {'BIL': 100, 'AAPL': 5000},
      );
      expect(p.saved, 100);
      expect(p.status, GoalProgressStatus.behind);
      expect(p.requiredMonthlyNow, greaterThan(p.plannedMonthly));
      expect(p.toBrief()['counted_holdings'], {'BIL': 100});
    });

    test('having the money (in the app or outside) is achieved, never '
        'behind', () {
      final inApp = GoalProgress.of(
        _goal(),
        DateTime(2026, 3, 2),
        holdings: {'BIL': 1300},
      );
      expect(inApp.status, GoalProgressStatus.achieved);
      final outside = GoalProgress.of(_goal(outside: 1200), DateTime(2026, 3, 2));
      expect(outside.status, GoalProgressStatus.achieved);
      expect(outside.fraction, 1);
    });

    test('a bit ahead of plan: ahead', () {
      final p = GoalProgress.of(
        _goal(outside: 600),
        DateTime(2026, 3, 2),
      );
      expect(p.status, GoalProgressStatus.ahead);
    });

    test('past the date without the amount: overdue', () {
      final p = GoalProgress.of(
        _goal(outside: 300),
        DateTime(2027, 2, 1),
      );
      expect(p.status, GoalProgressStatus.overdue);
    });
  });

  group('saving a goal from the chat', () {
    AssistantToolContext ctx({
      List<UserGoal> goals = const [],
      List<GoalDraft>? saved,
    }) => AssistantToolContext(
      tier: SubscriptionTier.premium,
      data: fakeDataSources(),
      summary: heldSummary,
      savedGoals: goals,
      saveGoal: (draft) async {
        saved?.add(draft);
        return _goal();
      },
      updateGoalSavings: (id, amount) async => _goal(outside: amount),
      now: DateTime(2026, 2, 2),
    );

    test('the plan result becomes a draft with the plan inside', () async {
      final c = ctx();
      final result = await GetGoalProjectionTool(c).run({
        'target_amount': 2500,
        'target_date': '2026-12-01',
        'goal_label': 'MacBook M5 Pro',
        'goal_type': 'purchase',
      });
      final draft = GoalDraft.fromToolResult(result)!;
      expect(draft.label, 'MacBook M5 Pro');
      expect(draft.type, GoalType.purchase);
      expect(draft.targetAmount, 2500);
      expect(draft.planKey, result['plan_id']);
      expect(draft.snapshot.inputs.shortTerm, isTrue);
      // Ida y vuelta por la columna jsonb.
      final back = GoalPlanSnapshot.fromJson(draft.snapshot.toJson())!;
      expect(back.inputs.targetAmount, 2500);
      // Sin compra mensual armada, se guarda con los instrumentos del plan.
      expect([for (final e in draft.snapshot.buyPlan) e.ticker], ['SGOV', 'VGSH']);
    });

    test('save_goal stores the latest plan of the conversation in Metas', () async {
      final saved = <GoalDraft>[];
      final c = ctx(saved: saved);
      await GetGoalProjectionTool(c).run({
        'target_amount': 2500,
        'target_date': '2026-12-01',
        'goal_label': 'MacBook',
        'goal_type': 'purchase',
      });
      final result = await SaveGoalTool(c).run(const {});
      expect(result['status'], 'ok');
      expect(result['where'], 'the Metas tab');
      expect(saved.single.label, 'MacBook');
    });

    test('saved goals travel in the brief with their progress, and a '
        'outside-savings update comes back with the updated progress', () async {
      final c = ctx(goals: [_goal()]);
      final brief = PortfolioBrief.build(c)[PortfolioBrief.savedGoalsKey]!;
      final first = (brief as List).single as Map;
      expect(first['id'], 'g1');
      expect(first['label'], 'MacBook');
      expect(first.containsKey('required_monthly_from_now'), isTrue);

      final result = await UpdateGoalSavingsTool(c).run({
        'goal_id': 'g1',
        'outside_savings_usd': 1500,
      });
      expect(result['status'], 'ok');
      // 1.500 afuera ≥ 1.200 de la meta: ya la tiene.
      expect((result['progress']! as Map)['status'], 'achieved');
      expect((result['progress']! as Map)['outside_savings'], 1500);
      expect(
        (await UpdateGoalSavingsTool(c).run({
          'goal_id': 'g7',
          'outside_savings_usd': 1,
        }))['reason'],
        'unknown_goal_id',
      );
    });
  });
}
