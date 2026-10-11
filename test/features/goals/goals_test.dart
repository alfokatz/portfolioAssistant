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
  List<GoalContribution> contributions = const [],
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
    contributions: contributions,
  );
}

GoalContribution _c(double amount, DateTime date) =>
    GoalContribution(id: '$amount-$date', amount: amount, date: date);

void main() {
  group('GoalProgress', () {
    test('just saved: just started', () {
      final p = GoalProgress.of(_goal(), DateTime(2026, 1, 10));
      expect(p.status, GoalProgressStatus.justStarted);
      expect(p.monthsRemaining, 12);
      expect(p.plannedMonthly, greaterThan(90));
    });

    test('contributing what the plan says: on track', () {
      final monthly = GoalProgress.of(_goal(), DateTime(2026, 1, 10))
          .plannedMonthly;
      final goal = _goal(
        contributions: [
          for (var m = 1; m <= 6; m++) _c(monthly, DateTime(2026, m, 28)),
        ],
      );
      final p = GoalProgress.of(goal, DateTime(2026, 7, 2));
      expect(p.monthsElapsed, 6);
      expect(p.status, GoalProgressStatus.onTrack);
    });

    test('contributing less: behind, and it says how much per month now', () {
      final goal = _goal(contributions: [_c(100, DateTime(2026, 2, 1))]);
      final p = GoalProgress.of(goal, DateTime(2026, 7, 2));
      expect(p.status, GoalProgressStatus.behind);
      expect(p.difference, lessThan(0));
      expect(p.requiredMonthlyNow, greaterThan(p.plannedMonthly));
      expect(p.toBrief()['status'], 'behind');
    });

    test('more than planned: ahead; the full amount: achieved', () {
      final ahead = GoalProgress.of(
        _goal(contributions: [_c(900, DateTime(2026, 2, 1))]),
        DateTime(2026, 3, 2),
      );
      expect(ahead.status, GoalProgressStatus.ahead);
      final done = GoalProgress.of(
        _goal(contributions: [_c(1200, DateTime(2026, 5, 1))]),
        DateTime(2026, 5, 2),
      );
      expect(done.status, GoalProgressStatus.achieved);
      expect(done.fraction, 1);
    });

    test('past the date without the amount: overdue', () {
      final p = GoalProgress.of(
        _goal(contributions: [_c(300, DateTime(2026, 3, 1))]),
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
      addGoalContribution:
          (id, amount, note) async =>
              _goal(contributions: [_c(amount, DateTime(2026, 2, 1))]),
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
        'contribution comes back with the updated progress', () async {
      final c = ctx(goals: [_goal()]);
      final brief = PortfolioBrief.build(c)[PortfolioBrief.savedGoalsKey]!;
      final first = (brief as List).single as Map;
      expect(first['id'], 'g1');
      expect(first['label'], 'MacBook');
      expect(first.containsKey('required_monthly_from_now'), isTrue);

      final result = await AddGoalContributionTool(c).run({
        'goal_id': 'g1',
        'amount_usd': 200,
      });
      expect(result['status'], 'ok');
      expect((result['progress']! as Map)['saved'], 200);
      expect(
        (await AddGoalContributionTool(c).run({
          'goal_id': 'g7',
          'amount_usd': 1,
        }))['reason'],
        'unknown_goal_id',
      );
    });
  });
}
