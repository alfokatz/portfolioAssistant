import 'package:portfolio_assistant/features/assistant/data/plan/plan_projection_calculator.dart';

/// Meta financiera activa + proyección lineal + hitos. El monto, la fecha y
/// el nombre de la meta los extrae el modelo del mensaje (argumentos de la
/// tool); acá solo se combinan con la meta guardada y se calcula — el
/// modelo nunca hace la cuenta.
abstract final class GoalProjectionBuilder {
  static const projectionDisclaimer =
      'Proyección lineal ilustrativa sin rendimientos de mercado.';

  static Map<String, Object?> build({
    required double currentPortfolioValue,
    double? targetAmount,
    DateTime? targetDate,
    String? label,
    double? monthlyContribution,
    ({String label, double targetAmount, String targetDate})? savedGoal,
    DateTime? asOf,
  }) {
    final reference = asOf ?? DateTime.now();
    final hasStated = targetAmount != null || targetDate != null;

    final saved =
        savedGoal == null
            ? null
            : <String, Object?>{
              'label': savedGoal.label,
              'target_amount': savedGoal.targetAmount,
              'target_date': savedGoal.targetDate,
            };
    final stated = <String, Object?>{
      if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
      if (targetAmount != null) 'target_amount': targetAmount,
      if (targetDate != null) 'target_date': formatDate(targetDate),
    };

    // Lo que el usuario dijo en este mensaje gana campo por campo sobre la
    // meta guardada; lo que no dijo se completa con la guardada.
    final active =
        !hasStated && saved != null
            ? saved
            : <String, Object?>{
              'label': stated['label'] ?? saved?['label'] ?? 'Mi meta',
              'target_amount':
                  stated['target_amount'] ?? saved?['target_amount'],
              'target_date': stated['target_date'] ?? saved?['target_date'],
            };
    final complete =
        active['target_amount'] != null && active['target_date'] != null;

    final result = <String, Object?>{
      'current_portfolio_value': currentPortfolioValue,
      'monthly_contribution': monthlyContribution,
      'saved_goal': saved,
      'active_goal': active,
      'has_complete_goal': complete,
      'projection_disclaimer': projectionDisclaimer,
    };
    if (!complete) {
      result['missing'] = [
        if (active['target_amount'] == null) 'target_amount',
        if (active['target_date'] == null) 'target_date',
      ];
      return result;
    }

    final projection = PlanProjectionCalculator.compute(
      targetAmount: (active['target_amount']! as num).toDouble(),
      currentAmount: currentPortfolioValue,
      targetDate: DateTime.parse(active['target_date']! as String),
      asOf: reference,
      monthlyContribution: monthlyContribution,
    );
    result['projection'] = {
      'target_amount': projection.targetAmount,
      'current_amount': projection.currentAmount,
      'months_remaining': projection.monthsRemaining,
      'required_monthly_savings': projection.requiredMonthlySavings,
      'projected_amount_at_date': projection.projectedAmountAtDate,
      'on_track': projection.onTrack,
      'monthly_contribution_used': projection.monthlyContribution,
    };
    result['milestones'] = [
      for (final m in PlanProjectionCalculator.milestones(
        projection: projection,
        asOf: reference,
      ))
        {
          'label': m.label,
          'amount': m.amount,
          'target_date': formatDate(m.targetDate),
        },
    ];
    return result;
  }

  static String formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
