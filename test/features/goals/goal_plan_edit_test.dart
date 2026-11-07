import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/assistant/tools/advice_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';

import '../assistant/fakes/assistant_fakes.dart';

/// La MacBook ya guardada en Metas: 2000 para dentro de un año.
UserGoal _macbook() {
  final inputs = SavingsPlanInputs(
    targetAmount: 2000,
    months: 12,
    currentAmount: 0,
    risk: RiskTolerance.moderate,
    startDate: DateTime(2026, 10, 11),
    shortTerm: true,
  );
  return UserGoal(
    id: 'goal-mac',
    label: 'MacBook M5 Pro',
    type: GoalType.purchase,
    targetAmount: 2000,
    targetDate: DateTime(2027, 10, 11),
    snapshot: GoalPlanSnapshot(inputs: inputs),
    status: GoalStatus.active,
    createdAt: DateTime(2026, 10, 11),
  );
}

AssistantToolContext _ctx({List<UserGoal> goals = const []}) =>
    AssistantToolContext(
      tier: SubscriptionTier.premium,
      data: fakeDataSources(),
      summary: heldSummary,
      savedGoals: goals,
      now: DateTime(2026, 10, 11),
    );

Map<String, Object?> _goal(Map<String, Object?> result) =>
    (result['active_goal']! as Map).cast<String, Object?>();

void main() {
  group('a new goal never borrows a saved one', () {
    test('"una silla de 2000" without a date asks for it, and never becomes '
        'the MacBook', () async {
      final tool = GetGoalProjectionTool(_ctx(goals: [_macbook()]));
      final result = await tool.run({
        'target_amount': 2000,
        'goal_label': 'Silla Herman Miller',
        'goal_type': 'purchase',
      });
      expect(result['has_complete_goal'], isFalse);
      expect(result['missing'], ['target_date']);
      expect(_goal(result)['label'], 'Silla Herman Miller');
      expect(_goal(result)['target_date'], isNull);
    });

    test('with the date it is its own goal', () async {
      final tool = GetGoalProjectionTool(_ctx(goals: [_macbook()]));
      final result = await tool.run({
        'target_amount': 2000,
        'target_date': '2028-10-11',
        'goal_label': 'Silla Herman Miller',
        'goal_type': 'purchase',
      });
      expect(_goal(result)['label'], 'Silla Herman Miller');
      expect(_goal(result)['target_date'], '2028-10-11');
    });

    test('goal_id fills what is not stated from THAT saved goal', () async {
      final tool = GetGoalProjectionTool(_ctx(goals: [_macbook()]));
      final result = await tool.run({
        'goal_id': 'g1',
        'target_date': '2028-10-11',
      });
      expect(result['has_complete_goal'], isTrue);
      expect(_goal(result)['label'], 'MacBook M5 Pro');
      expect(_goal(result)['target_amount'], 2000);
      expect(_goal(result)['target_date'], '2028-10-11');
      expect(result['goal_type'], GoalProjectionBuilder.goalPurchase);
    });
  });

  test('redoing a saved goal\'s plan starts from what it already has, not '
      'from 0', () async {
    final saved = _macbook();
    final withSavings = UserGoal(
      id: saved.id,
      label: saved.label,
      type: saved.type,
      targetAmount: saved.targetAmount,
      targetDate: saved.targetDate,
      snapshot: saved.snapshot,
      status: saved.status,
      createdAt: saved.createdAt,
      externalSavings: 450,
    );
    final result = await GetGoalProjectionTool(
      _ctx(goals: [withSavings]),
    ).run({'goal_id': 'g1'});
    expect(result['starting_capital'], 450);
  });

  group('changing a plan of the chat', () {
    test('base_plan_id keeps everything but what changes', () async {
      final ctx = _ctx();
      final tool = GetGoalProjectionTool(ctx);
      final first = await tool.run({
        'target_amount': 2000,
        'target_date': '2027-10-11',
        'goal_label': 'Silla',
        'goal_type': 'purchase',
        'current_savings': 300,
      });
      final changed = await tool.run({
        'base_plan_id': first['plan_id'],
        'target_date': '2028-10-11',
      });
      expect(changed['plan_id'], isNot(first['plan_id']));
      expect(_goal(changed)['label'], 'Silla');
      expect(_goal(changed)['target_amount'], 2000);
      expect(_goal(changed)['target_date'], '2028-10-11');
      expect(changed['starting_capital'], 300);
      expect(changed['goal_type'], GoalProjectionBuilder.goalPurchase);
    });

    test('Porty builds on what the user edited in the card', () async {
      final ctx = _ctx();
      final tool = GetGoalProjectionTool(ctx);
      final first = await tool.run({
        'target_amount': 2000,
        'target_date': '2027-10-11',
        'goal_label': 'Mi meta',
        'goal_type': 'purchase',
      });
      final edited =
          GoalProjectionBuilder.edit(
            first,
            label: 'Silla Herman Miller',
            targetAmount: 1800,
          )!;
      ctx.data.plans.recordEdit(
        first['plan_id']! as String,
        edited['plan_id']! as String,
        edited,
      );
      final changed = await tool.run({
        'base_plan_id': first['plan_id'],
        'target_date': '2028-04-11',
      });
      expect(_goal(changed)['label'], 'Silla Herman Miller');
      expect(_goal(changed)['target_amount'], 1800);
      expect(_goal(changed)['target_date'], '2028-04-11');

      // Guardar el plan original guarda lo que el usuario editó.
      expect(
        _goal(ctx.data.plans.lookup(first['plan_id']! as String)!)['label'],
        'Silla Herman Miller',
      );
    });
  });

  group('editing in the card', () {
    final original = GoalProjectionBuilder.build(
      currentPortfolioValue: 10000,
      targetAmount: 25000,
      targetDate: DateTime(2029, 10, 11),
      label: 'Auto',
      isPurchase: true,
      asOf: DateTime(2026, 10, 11),
    );

    test('a later date leaves the short term: the risk is used again', () {
      final edited =
          GoalProjectionBuilder.edit(
            original,
            targetDate: DateTime(2033, 10, 11),
            risk: RiskTolerance.aggressive,
          )!;
      expect(edited['short_term_purchase'], isFalse);
      expect(edited['edited_by_user'], isTrue);
      expect(edited['plan_id'], isNot(original['plan_id']));
      final inputs =
          SavingsPlanInputs.fromJson((edited['plan']! as Map)['inputs'])!;
      expect(inputs.months, 84);
      expect(inputs.risk, RiskTolerance.aggressive);
      expect(inputs.shortTerm, isFalse);
    });

    test('name, amount and savings become the goal to confirm', () {
      final edited =
          GoalProjectionBuilder.edit(
            original,
            label: 'Auto usado',
            targetAmount: 18000,
            currentAmount: 3000,
          )!;
      final draft = GoalDraft.fromToolResult(edited)!;
      expect(draft.label, 'Auto usado');
      expect(draft.targetAmount, 18000);
      expect(draft.snapshot.inputs.currentAmount, 3000);
      expect(draft.snapshot.inputs.shortTerm, isTrue);
      expect(draft.planKey, edited['plan_id']);
      expect(edited['starting_capital_source'], 'stated');
      expect(
        [for (final e in draft.snapshot.buyPlan) e.ticker],
        ['SGOV', 'VGSH'],
      );
    });
  });
}
