// Planes de metas en la moneda del usuario: get_goal_projection con
// `currency` arma el plan en esa moneda (sin convertir lo que dijo), pasa la
// cartera de dólares a esa moneda y la meta guardada queda en ella.
// Correr: flutter test test/features/assistant/tools/goal_currency_tools_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/assistant/tools/advice_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_currency.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';

import '../fakes/assistant_fakes.dart';

AssistantToolContext _ctx({
  double? rate = 40,
  List<UserGoal> goals = const [],
}) => AssistantToolContext(
  tier: SubscriptionTier.gold,
  data: fakeDataSources(),
  summary: heldSummary,
  savedGoals: goals,
  loadFxRate: (code) async => code == 'UYU' ? rate : null,
  now: DateTime.utc(2026, 9, 29),
);

SavingsPlanInputs _inputs(Map<String, Object?> result) =>
    SavingsPlanInputs.fromJson((result['plan']! as Map)['inputs'])!;

void main() {
  test('una meta dicha en pesos se arma en pesos: los montos quedan como '
      'los dijo y el plan lo dice', () async {
    final result = await GetGoalProjectionTool(_ctx()).run({
      'target_amount': 1000000,
      'months_from_now': 36,
      'goal_label': 'Auto',
      'goal_type': 'purchase',
      'monthly_contribution': 20000,
      'currency': 'UYU',
    });
    expect(result['status'], 'ok');
    expect(result['currency'], 'UYU');
    final inputs = _inputs(result);
    expect(inputs.currency, 'UYU');
    expect(inputs.targetAmount, 1000000);
    expect(inputs.monthlyContribution, 20000);
    // Al guardarla desde el chat, la meta queda en pesos.
    expect(GoalDraft.fromToolResult(result)!.currency, DisplayCurrency.uyu);
  });

  test('la cartera (en dólares) se pasa a la moneda del plan', () async {
    final usd = await GetGoalProjectionTool(_ctx()).run({
      'target_amount': 500000,
      'months_from_now': 240,
      'goal_label': 'Jubilación',
      'is_retirement': true,
    });
    final uyu = await GetGoalProjectionTool(_ctx()).run({
      'target_amount': 20000000,
      'months_from_now': 240,
      'goal_label': 'Jubilación',
      'is_retirement': true,
      'currency': 'UYU',
    });
    expect(
      uyu['current_portfolio_value'],
      closeTo((usd['current_portfolio_value']! as num) * 40, 1e-6),
    );
    expect(
      _inputs(uyu).currentAmount,
      closeTo(_inputs(usd).currentAmount * 40, 1e-6),
    );
  });

  test('sin tipo de cambio no arma un plan en esa moneda (lo dice)', () async {
    final result = await GetGoalProjectionTool(_ctx(rate: null)).run({
      'target_amount': 1000000,
      'months_from_now': 36,
      'goal_label': 'Auto',
      'currency': 'UYU',
    });
    expect(result['status'], 'failed');
    expect(result['reason'], 'fx_rate_unavailable');
  });

  test('en dólares nada cambia: ni la clave currency ni el plan_id', () async {
    final args = {
      'target_amount': 1500,
      'target_date': '2027-06-01',
      'goal_label': 'Computadora',
      'goal_type': 'purchase',
    };
    final a = await GetGoalProjectionTool(_ctx()).run(args);
    final b = await GetGoalProjectionTool(
      _ctx(),
    ).run({...args, 'currency': 'USD'});
    expect(a.containsKey('currency'), isFalse);
    expect(a['plan_id'], b['plan_id']);
    expect((a['plan']! as Map)['inputs'], isNot(contains('currency')));
  });

  test(
    'una meta guardada en pesos se rehace en pesos aunque no lo diga',
    () async {
      final draft =
          GoalDraft.fromToolResult(
            await GetGoalProjectionTool(_ctx()).run({
              'target_amount': 1000000,
              'months_from_now': 36,
              'goal_label': 'Auto',
              'goal_type': 'purchase',
              'currency': 'UYU',
            }),
          )!;
      final goal = UserGoal(
        id: 'g',
        label: draft.label,
        type: draft.type,
        targetAmount: draft.targetAmount,
        targetDate: draft.targetDate,
        snapshot: draft.snapshot,
        status: GoalStatus.active,
        createdAt: DateTime.utc(2026, 9, 1),
        currency: DisplayCurrency.uyu,
        fxRate: 40,
      );
      final result = await GetGoalProjectionTool(
        _ctx(goals: [goal]),
      ).run({'goal_id': 'g1', 'months_from_now': 24});
      expect(result['status'], 'ok');
      expect(_inputs(result).currency, 'UYU');
    },
  );
}
