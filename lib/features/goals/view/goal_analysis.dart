import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_progress.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// El "análisis de Porty" de una meta: una o dos frases armadas con los
/// números de [GoalProgress] (nunca las escribe el modelo).
abstract final class GoalAnalysis {
  static String text(UserGoal goal, GoalProgress p, Locale locale) {
    String money(double v) => QaFormat.money(v);
    final date = DateFormat.yMMMM(
      locale.toLanguageTag(),
    ).format(goal.targetDate);
    final args = {
      'saved': money(p.saved),
      'target': money(p.target),
      'monthly': money(p.plannedMonthly),
      'required': money(p.requiredMonthlyNow),
      'expected': money(p.expected),
      'diff': money(p.difference.abs()),
      'missing': money((p.target - p.saved).clamp(0, double.infinity)),
      'date': date,
    };
    return 'goal_analysis_${p.status.key}'.tr(namedArgs: args);
  }

  /// Cuánto falta, dicho como lo diría alguien y en pocas palabras (entra
  /// en la fila de la meta): en meses hasta los dos años ("faltan 16
  /// meses", "falta 1 mes"), después en años redondeados ("faltan 7 años");
  /// "vence este mes", "venció en oct 2027". Cumplida: el mes en que era.
  static String timeLeft(UserGoal goal, GoalProgress p, Locale locale) {
    String date() =>
        DateFormat.yMMM(locale.toLanguageTag()).format(goal.targetDate);
    if (p.status == GoalProgressStatus.achieved) return date();
    if (p.status == GoalProgressStatus.overdue) {
      return 'goals_left_overdue'.tr(namedArgs: {'date': date()});
    }
    final months = p.monthsRemaining;
    if (months <= 0) return 'goals_left_this_month'.tr();
    if (months == 1) {
      return 'goals_left_one'.tr(namedArgs: {'time': 'goals_left_month'.tr()});
    }
    final time =
        months < 24
            ? 'goals_left_months'.tr(namedArgs: {'n': '$months'})
            : 'goals_left_years'.tr(
              namedArgs: {'n': '${(months / 12).round()}'},
            );
    return 'goals_left'.tr(namedArgs: {'time': time});
  }

  /// "6 %" (o "<1 %" si recién empieza a sumar; "0 %" sin nada).
  static String percent(double fraction) {
    if (fraction > 0 && fraction < 0.01) {
      return 'goals_percent_tiny'.tr();
    }
    return NumberFormat.percentPattern().format(fraction);
  }

  static String statusLabel(GoalProgressStatus status) =>
      'goal_status_${status.key}'.tr();

  static Color statusColor(GoalProgressStatus status, CustomColors colors) =>
      switch (status) {
        GoalProgressStatus.achieved ||
        GoalProgressStatus.ahead ||
        GoalProgressStatus.onTrack => colors.profit,
        GoalProgressStatus.behind || GoalProgressStatus.overdue => colors.loss,
        GoalProgressStatus.justStarted => colors.onChip,
      };
}
