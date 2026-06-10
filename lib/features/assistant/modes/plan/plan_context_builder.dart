import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/features/assistant/modes/plan/goal_extractor.dart';
import 'package:portfolio_assistant/features/assistant/modes/plan/plan_projection_calculator.dart';

/// Construye el snapshot de contexto para modo plan.
abstract final class PlanContextBuilder {
  static const _projectionDisclaimer =
      'Proyección lineal ilustrativa sin rendimientos de mercado.';

  static Future<Map<String, Object?>> build({
    required String userMessage,
    PortfolioSummary? summary,
    ({String label, double targetAmount, String targetDate})? savedGoal,
    double? monthlyContribution,
    DateTime? asOf,
  }) async {
    final reference = asOf ?? DateTime.now();
    final timestamp = reference.toUtc().toIso8601String();
    final currentValue = summary?.totalValue ?? 0.0;

    final parsedAmount = GoalExtractor.extractTargetAmount(userMessage);
    final parsedDate = GoalExtractor.extractTargetDate(
      userMessage,
      asOf: reference,
    );
    final parsedLabel = GoalExtractor.extractGoalLabel(userMessage);
    final hasParsedGoal = parsedAmount != null || parsedDate != null;

    final parsedGoal = _goalMap(
      label: parsedLabel,
      targetAmount: parsedAmount,
      targetDate: parsedDate != null ? _formatDate(parsedDate) : null,
    );

    final savedGoalMap =
        savedGoal == null
            ? null
            : _goalMap(
              label: savedGoal.label,
              targetAmount: savedGoal.targetAmount,
              targetDate: savedGoal.targetDate,
            );

    final activeGoal = _mergeGoals(
      saved: savedGoalMap,
      parsed: parsedGoal,
      preferParsed: hasParsedGoal,
    );
    final hasCompleteGoal = _isCompleteGoal(activeGoal);

    final snapshot = <String, Object?>{
      'mode': 'plan',
      'data_source': 'computed',
      'as_of': timestamp,
      'current_portfolio_value': currentValue,
      'monthly_contribution': monthlyContribution,
      'saved_goal': savedGoalMap,
      'parsed_goal': hasParsedGoal ? parsedGoal : null,
      'active_goal': activeGoal,
      'has_complete_goal': hasCompleteGoal,
      'projection_disclaimer': _projectionDisclaimer,
    };

    if (!hasCompleteGoal) {
      snapshot['projection'] = null;
      snapshot['milestones'] = null;
      return snapshot;
    }

    final targetAmount = activeGoal!['target_amount']! as double;
    final targetDate = DateTime.parse(activeGoal['target_date']! as String);

    final projection = PlanProjectionCalculator.compute(
      targetAmount: targetAmount,
      currentAmount: currentValue,
      targetDate: targetDate,
      asOf: reference,
      monthlyContribution: monthlyContribution,
    );

    final milestoneEntries =
        PlanProjectionCalculator.milestones(
          projection: projection,
          asOf: reference,
        ).map(_milestoneMap).toList();

    snapshot['projection'] = _projectionMap(projection);
    snapshot['milestones'] = milestoneEntries;

    return snapshot;
  }

  static Map<String, Object?>? _goalMap({
    required String label,
    double? targetAmount,
    String? targetDate,
  }) {
    if (targetAmount == null && targetDate == null) {
      return {'label': label};
    }

    return {
      'label': label,
      if (targetAmount != null) 'target_amount': targetAmount,
      if (targetDate != null) 'target_date': targetDate,
    };
  }

  static Map<String, Object?>? _mergeGoals({
    required Map<String, Object?>? saved,
    required Map<String, Object?>? parsed,
    required bool preferParsed,
  }) {
    if (saved == null && parsed == null) return null;
    if (saved == null) return parsed;
    if (parsed == null || !preferParsed) return saved;

    return {
      'label': parsed['label'] ?? saved['label'],
      'target_amount': parsed['target_amount'] ?? saved['target_amount'],
      'target_date': parsed['target_date'] ?? saved['target_date'],
    };
  }

  static bool _isCompleteGoal(Map<String, Object?>? goal) {
    if (goal == null) return false;
    return goal['target_amount'] != null && goal['target_date'] != null;
  }

  static Map<String, Object?> _projectionMap(PlanProjection projection) {
    return {
      'target_amount': projection.targetAmount,
      'current_amount': projection.currentAmount,
      'months_remaining': projection.monthsRemaining,
      'required_monthly_savings': projection.requiredMonthlySavings,
      'projected_amount_at_date': projection.projectedAmountAtDate,
      'on_track': projection.onTrack,
      'monthly_contribution_used': projection.monthlyContribution,
    };
  }

  static Map<String, Object?> _milestoneMap(PlanMilestone milestone) {
    return {
      'label': milestone.label,
      'amount': milestone.amount,
      'target_date': _formatDate(milestone.targetDate),
    };
  }

  static String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
