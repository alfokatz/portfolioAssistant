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
    final date = DateFormat.yMMMM(locale.toLanguageTag()).format(goal.targetDate);
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

  static String statusLabel(GoalProgressStatus status) =>
      'goal_status_${status.key}'.tr();

  static Color statusColor(GoalProgressStatus status, CustomColors colors) =>
      switch (status) {
        GoalProgressStatus.achieved ||
        GoalProgressStatus.ahead ||
        GoalProgressStatus.onTrack => colors.profit,
        GoalProgressStatus.behind || GoalProgressStatus.overdue => colors.loss,
        GoalProgressStatus.justStarted => colors.accentBlue,
      };
}
