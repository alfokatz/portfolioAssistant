import 'dart:math' as math;

import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';

enum GoalProgressStatus {
  /// Recién guardada, todavía sin aportes ni meses transcurridos.
  justStarted('just_started'),
  onTrack('on_track'),
  ahead('ahead'),
  behind('behind'),
  achieved('achieved'),

  /// Pasó la fecha sin llegar al monto.
  overdue('overdue');

  const GoalProgressStatus(this.key);
  final String key;
}

/// ¿Va en camino? Compara lo que lleva juntado (sus inversiones asignadas a
/// la meta + lo que tiene afuera; ver [UserGoal.savedWith]) con lo que el
/// plan esperaba
/// a esta altura (mismo cálculo que el plan: aportes mensuales con el
/// rendimiento del escenario base) y calcula cuánto tendría que aportar
/// desde hoy para llegar en fecha. Todo determinístico: el análisis no lo
/// escribe el modelo.
class GoalProgress {
  const GoalProgress({
    required this.status,
    required this.saved,
    required this.expected,
    required this.target,
    required this.plannedMonthly,
    required this.requiredMonthlyNow,
    required this.monthsElapsed,
    required this.monthsRemaining,
    this.linkedValues = const {},
    this.externalSavings = 0,
  });

  final GoalProgressStatus status;
  final double saved;

  /// Lo que el plan esperaba juntado a esta altura.
  final double expected;
  final double target;

  /// El aporte mensual del plan.
  final double plannedMonthly;

  /// El aporte mensual necesario desde hoy para llegar en fecha.
  final double requiredMonthlyNow;
  final int monthsElapsed;
  final int monthsRemaining;

  /// Cuánto aporta hoy cada inversión asignada que tiene.
  final Map<String, double> linkedValues;
  final double externalSavings;

  double get fraction => target <= 0 ? 0 : (saved / target).clamp(0.0, 1.0);

  /// Positivo = adelantado, negativo = atrasado.
  double get difference => saved - expected;

  /// [holdings] = valor de mercado por ticker de la cartera (en
  /// mayúsculas).
  static GoalProgress of(
    UserGoal goal,
    DateTime now, {
    Map<String, double> holdings = const {},
  }) {
    final inputs = goal.snapshot.inputs;
    final plan = goal.snapshot.plan;
    final baseReturn = plan.returns[PlanScenario.base]!;
    final total = math.max(1, inputs.months);
    final elapsed = _wholeMonths(inputs.startDate, now).clamp(0, total);
    final remaining = math.max(0, total - elapsed);
    final monthly = plan.monthlyUsed;
    final linkedValues = goal.linkedValues(holdings);
    final saved = goal.savedWith(holdings);
    final expected = SavingsPlanCalculator.futureValue(
      current: inputs.currentAmount,
      monthly: monthly,
      months: elapsed,
      annualReturn: baseReturn,
    );
    final required = SavingsPlanCalculator.requiredMonthly(
      target: goal.targetAmount,
      current: saved,
      months: math.max(1, remaining),
      annualReturn: baseReturn,
    );
    // Medio aporte (o 1% de la meta) de margen: un mes de diferencia no
    // cambia el veredicto.
    final tolerance = math.max(monthly * 0.5, goal.targetAmount * 0.01);
    final diff = saved - expected;
    final status =
        goal.status == GoalStatus.achieved || saved >= goal.targetAmount - 0.5
            ? GoalProgressStatus.achieved
            : now.isAfter(goal.targetDate)
            ? GoalProgressStatus.overdue
            : elapsed == 0 && saved <= 0
            ? GoalProgressStatus.justStarted
            : diff >= tolerance
            ? GoalProgressStatus.ahead
            : diff <= -tolerance
            ? GoalProgressStatus.behind
            : GoalProgressStatus.onTrack;
    return GoalProgress(
      status: status,
      saved: saved,
      expected: expected,
      target: goal.targetAmount,
      plannedMonthly: monthly,
      requiredMonthlyNow: required,
      monthsElapsed: elapsed,
      monthsRemaining: remaining,
      linkedValues: linkedValues,
      externalSavings: goal.externalSavings,
    );
  }

  /// Para PORTFOLIO_BRIEF: el modelo cita estos números al hablar de la
  /// meta, nunca los recalcula.
  Map<String, Object?> toBrief() {
    int r(double v) => v.round();
    return {
      'status': status.key,
      'saved': r(saved),
      'expected_by_now': r(expected),
      'planned_monthly': r(plannedMonthly),
      'required_monthly_from_now': r(requiredMonthlyNow),
      'months_remaining': monthsRemaining,
      'counted_holdings': {
        for (final e in linkedValues.entries) e.key: r(e.value),
      },
      'outside_savings': r(externalSavings),
    };
  }

  static int _wholeMonths(DateTime start, DateTime now) {
    var months = (now.year - start.year) * 12 + (now.month - start.month);
    if (now.day < start.day) months--;
    return months;
  }

  /// La fecha como la escribe el plan (YYYY-MM-DD).
  static String formatDate(DateTime date) =>
      GoalProjectionBuilder.formatDate(date);
}
