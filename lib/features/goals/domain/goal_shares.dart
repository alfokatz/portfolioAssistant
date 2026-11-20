import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';

/// Varias metas pueden contar la misma inversión (BND para la jubilación y
/// para el auto). Para no sumar dos veces la misma plata, su valor de
/// mercado se reparte entre las metas activas que la cuentan:
///
/// - Proporcional a lo que cada plan NECESITA poner por mes en ella (el
///   ahorro mensual necesario × el % de esa inversión en su compra): si la
///   jubilación necesita 103 $/mes en BND y el auto 72 $/mes, a la
///   jubilación le toca el 59 % de lo que hay en BND. No se usa el aporte
///   que dijo el usuario: uno mal cargado (20.000 pesos tomados como
///   dólares) se quedaba con casi toda la inversión.
/// - En partes iguales si alguna de esas metas no la tiene en su plan (la
///   eligió a mano en "Qué cuenta").
///
/// Una meta que no está activa (lograda, archivada) no le saca parte a las
/// activas; ella misma se calcula como si fuera una más.
abstract final class GoalShares {
  /// La fracción (0–1) de [ticker] que le toca a [goal], entre [goals].
  static double shareOf(
    UserGoal goal,
    String ticker,
    Iterable<UserGoal> goals,
  ) {
    final t = ticker.toUpperCase();
    if (!goal.linkedTickers.contains(t)) return 0;
    final sharers = [
      goal,
      for (final g in goals)
        if (g.id != goal.id &&
            g.status == GoalStatus.active &&
            g.linkedTickers.contains(t))
          g,
    ];
    if (sharers.length == 1) return 1;
    final weights = [for (final g in sharers) _planWeight(g, t)];
    if (weights.any((w) => w <= 0)) return 1 / sharers.length;
    return weights.first / weights.fold(0.0, (a, b) => a + b);
  }

  /// [holdings] (valor de mercado por ticker) visto desde [goal]: cada
  /// inversión que comparte con otras metas, solo con su parte.
  static Map<String, double> holdingsFor(
    UserGoal goal,
    Iterable<UserGoal> goals,
    Map<String, double> holdings,
  ) => {
    for (final e in holdings.entries)
      e.key:
          goal.linkedTickers.contains(e.key)
              ? e.value * shareOf(goal, e.key, goals)
              : e.value,
  };

  /// Las otras metas activas que también cuentan [ticker].
  static List<UserGoal> othersCounting(
    UserGoal goal,
    String ticker,
    Iterable<UserGoal> goals,
  ) => [
    for (final g in goals)
      if (g.id != goal.id &&
          g.status == GoalStatus.active &&
          g.linkedTickers.contains(ticker.toUpperCase()))
        g,
  ];

  static double _planWeight(UserGoal goal, String ticker) {
    final pct = goal.snapshot.buyPlan
        .where((e) => e.ticker.toUpperCase() == ticker)
        .fold(0.0, (a, e) => a + e.pct);
    if (pct <= 0) return 0;
    final needed = goal.snapshot.plan.requiredMonthly[PlanScenario.base] ?? 0;
    return needed * pct / 100;
  }
}
