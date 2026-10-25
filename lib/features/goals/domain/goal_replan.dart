import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';

/// El plan de una meta guardada, recalculado con lo que cambió.
///
/// La regla: el plan siempre parte de lo que la meta tiene de verdad, es
/// decir sus ahorros fuera de la app + el valor de hoy de sus inversiones
/// asignadas ([UserGoal.savedWith]). Cuando eso cambia (el usuario carga lo
/// de afuera, suma una inversión que ya tiene o edita el plan), el plan se
/// rehace desde hoy con el plazo que le queda y el aporte mensual se
/// recalcula. Todo determinístico: mismo cálculo que la card del chat.
abstract final class GoalReplan {
  /// Lo que la meta tiene hoy para el plan. [externalSavings] reemplaza al
  /// guardado (el editor del plan todavía no lo guardó).
  static double capital(
    UserGoal goal,
    Map<String, double> holdings, {
    double? externalSavings,
  }) => goal
      .linkedValues(holdings)
      .values
      .fold(externalSavings ?? goal.externalSavings, (a, b) => a + b);

  /// ¿El plan guardado ya parte de [capital]? (a dólar entero, como lo
  /// muestra la app).
  static bool startsFrom(UserGoal goal, double capital) =>
      goal.snapshot.inputs.currentAmount.round() == capital.round();

  /// El plan de [goal] rehecho desde [now] con [capital], o `null` si ya
  /// partía de ese monto (no hay nada que recalcular) o no está activa.
  static GoalDraft? rebase(UserGoal goal, double capital, DateTime now) {
    if (goal.status != GoalStatus.active || startsFrom(goal, capital)) {
      return null;
    }
    return draft(
      goal,
      currentAmount: capital,
      startDate: DateTime(now.year, now.month, now.day),
    );
  }

  /// [goal] con lo que cambió. Si la cartera sigue igual (mismo riesgo y
  /// plazo), se mantiene su compra mensual con los montos nuevos; si cambió,
  /// van los instrumentos del plan nuevo.
  static GoalDraft? draft(
    UserGoal goal, {
    String? label,
    double? targetAmount,
    DateTime? targetDate,
    double? currentAmount,
    RiskTolerance? risk,
    DateTime? startDate,
  }) {
    final inputs = goal.snapshot.inputs;
    final edited = GoalProjectionBuilder.edit(
      {
        'plan': {'inputs': inputs.toJson()},
        'active_goal': {
          'label': goal.label,
          'target_amount': goal.targetAmount,
          'target_date': GoalProjectionBuilder.formatDate(goal.targetDate),
        },
        if (goal.type == GoalType.purchase)
          'goal_type': GoalProjectionBuilder.goalPurchase,
      },
      label: label,
      targetAmount: targetAmount,
      targetDate: targetDate,
      currentAmount:
          currentAmount != null && currentAmount != inputs.currentAmount
              ? currentAmount
              : null,
      risk: risk != null && risk != inputs.risk ? risk : null,
      startDate: startDate,
    );
    final draft = edited == null ? null : GoalDraft.fromToolResult(edited);
    if (draft == null) return null;
    final before = goal.snapshot.plan.allocation;
    final after = draft.snapshot.plan.allocation;
    final sameMix =
        before.length == after.length &&
        before.entries.every((e) => after[e.key] == e.value);
    if (!sameMix || goal.snapshot.buyPlan.isEmpty) {
      return GoalDraft(
        label: draft.label,
        type: goal.type,
        targetAmount: draft.targetAmount,
        targetDate: draft.targetDate,
        snapshot: draft.snapshot,
        planKey: draft.planKey,
      );
    }
    final monthly = draft.snapshot.plan.monthlyUsed;
    return GoalDraft(
      label: draft.label,
      type: goal.type,
      targetAmount: draft.targetAmount,
      targetDate: draft.targetDate,
      snapshot: GoalPlanSnapshot(
        inputs: draft.snapshot.inputs,
        buyPlan: [
          for (final e in goal.snapshot.buyPlan)
            GoalBuyPlanEntry(
              ticker: e.ticker,
              name: e.name,
              kind: e.kind,
              assetClassLabel: e.assetClassLabel,
              pct: e.pct,
              monthlyAmount: (monthly * e.pct / 100).round(),
            ),
        ],
      ),
      planKey: draft.planKey,
    );
  }
}
