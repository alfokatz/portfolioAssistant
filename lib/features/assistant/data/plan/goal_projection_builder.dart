import 'dart:convert';

import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';

/// Meta financiera activa + plan de ahorro con interés compuesto. El monto,
/// la fecha y el resto de los datos los extrae el modelo del mensaje
/// (argumentos de la tool); acá se combinan con la meta guardada y el perfil
/// y se calcula — el modelo nunca hace la cuenta.
abstract final class GoalProjectionBuilder {
  /// Clave del id del plan en el resultado: lo único que el modelo le pasa
  /// a la card `QaSavingsPlan`.
  static const planIdKey = 'plan_id';

  /// Tipos de meta (`goal_type` de la tool).
  static const goalRetirement = 'retirement';
  static const goalPurchase = 'purchase';
  static const goalOther = 'other';

  static const riskStated = 'stated';
  static const riskProfile = 'profile';
  static const riskDefault = 'default';

  static Map<String, Object?> build({
    required double currentPortfolioValue,
    double? targetAmount,
    DateTime? targetDate,
    String? label,
    double? monthlyContribution,
    double? currentSavings,
    double? desiredMonthlyIncome,
    bool? isRetirement,
    bool isPurchase = false,
    IncomeStrategy? incomeStrategy,
    double? dividendYield,
    RiskTolerance? statedRisk,
    InvestorProfile? profile,
    ({String label, double targetAmount, String targetDate})? savedGoal,
    DateTime? asOf,
  }) {
    final reference = asOf ?? DateTime.now();
    // "Quiero cobrar $3.000 por mes cuando me jubile" define la meta: el
    // capital que sostiene ese ingreso — de dividendos (sin tocar el
    // capital, por defecto) o retirando el 4% por año.
    final strategy = incomeStrategy ?? IncomeStrategy.dividends;
    final incomeTarget =
        targetAmount == null &&
                desiredMonthlyIncome != null &&
                desiredMonthlyIncome > 0
            ? switch (strategy) {
              IncomeStrategy.dividends =>
                SavingsPlanCalculator.capitalForDividends(
                  desiredMonthlyIncome,
                  dividendYield ?? PlanAssumptions.dividendYield,
                ),
              IncomeStrategy.withdrawal =>
                SavingsPlanCalculator.capitalForIncome(desiredMonthlyIncome),
            }
            : null;
    final statedAmount = targetAmount ?? incomeTarget;
    final hasStated = statedAmount != null || targetDate != null;

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
      if (statedAmount != null) 'target_amount': statedAmount,
      if (targetDate != null) 'target_date': formatDate(targetDate),
    };

    // Lo que el usuario dijo en este mensaje gana campo por campo sobre la
    // meta guardada; lo que no dijo se completa con la guardada.
    final active =
        !hasStated && saved != null
            ? saved
            : <String, Object?>{
              'label':
                  stated['label'] ??
                  saved?['label'] ??
                  (isRetirement == true || incomeTarget != null
                      ? 'Jubilación'
                      : 'Mi meta'),
              'target_amount':
                  stated['target_amount'] ?? saved?['target_amount'],
              'target_date': stated['target_date'] ?? saved?['target_date'],
            };
    final complete =
        active['target_amount'] != null && active['target_date'] != null;

    // Una compra (una compu, un viaje) no se paga con la cartera salvo que
    // el usuario lo diga: sin "ya tengo X para esto", se arranca de cero.
    final startingCapital =
        currentSavings ?? (isPurchase ? 0.0 : currentPortfolioValue);
    final result = <String, Object?>{
      'current_portfolio_value': currentPortfolioValue,
      'starting_capital': startingCapital,
      'starting_capital_source':
          currentSavings != null
              ? 'stated'
              : isPurchase
              ? 'assumed_zero'
              : 'portfolio_value',
      if (isPurchase) 'goal_type': goalPurchase,
      'monthly_contribution': monthlyContribution,
      'saved_goal': saved,
      'active_goal': active,
      if (incomeTarget != null)
        'target_from_income': {
          'desired_monthly_income': desiredMonthlyIncome,
          'strategy': strategy.key,
        },
      'has_complete_goal': complete,
    };
    if (!complete) {
      result['missing'] = [
        if (active['target_amount'] == null) 'target_amount',
        if (active['target_date'] == null) 'target_date',
      ];
      return result;
    }

    final date = DateTime.parse(active['target_date']! as String);
    final months = monthsBetween(reference, date);
    final retirement =
        !isPurchase &&
        (isRetirement ??
            (incomeTarget != null ||
                looksLikeRetirement('${active['label']}')));
    // Compra a menos de 3 años: liquidez y bonos cortos, sin acciones.
    final shortTermPurchase =
        isPurchase && months < PlanAssumptions.shortHorizonMonths;

    final chosenRisk = statedRisk ?? profile?.risk ?? RiskTolerance.moderate;
    final riskSource =
        statedRisk != null
            ? riskStated
            : profile != null
            ? riskProfile
            : riskDefault;
    // Plazo corto: la parte en acciones puede caer y no recuperarse a
    // tiempo, así que el plan va conservador aunque el perfil no lo sea.
    final shortHorizon =
        !shortTermPurchase &&
        months < PlanAssumptions.shortHorizonMonths &&
        chosenRisk != RiskTolerance.conservative;
    final risk = shortHorizon ? RiskTolerance.conservative : chosenRisk;

    final inputs = SavingsPlanInputs(
      targetAmount: (active['target_amount']! as num).toDouble(),
      months: months,
      currentAmount: startingCapital,
      risk: risk,
      startDate: DateTime(reference.year, reference.month, reference.day),
      monthlyContribution: monthlyContribution,
      isRetirement: retirement,
      desiredMonthlyIncome: incomeTarget != null ? desiredMonthlyIncome : null,
      incomeStrategy: strategy,
      dividendYield: dividendYield,
      shortTerm: shortTermPurchase,
    );
    final plan = SavingsPlan.build(inputs);
    result[planIdKey] = planIdFor(inputs);
    result['months_remaining'] = months;
    result['risk_source'] = riskSource;
    result['risk_adjusted_for_short_horizon'] = shortHorizon;
    result['short_term_purchase'] = shortTermPurchase;
    result['plan'] = plan.toToolResult();
    return result;
  }

  /// Id estable del plan: el mismo pedido da el mismo id.
  static String planIdFor(SavingsPlanInputs inputs) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(jsonEncode(inputs.toJson()))) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'plan-${hash.toRadixString(16).padLeft(8, '0')}';
  }

  static bool looksLikeRetirement(String label) {
    final l = label.toLowerCase();
    return const [
      'jubila',
      'retiro',
      'retirarme',
      'pensión',
      'pension',
    ].any(l.contains);
  }

  static int monthsBetween(DateTime start, DateTime end) {
    final months = (end.year - start.year) * 12 + (end.month - start.month);
    return months < 1 ? 1 : months;
  }

  static String formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
