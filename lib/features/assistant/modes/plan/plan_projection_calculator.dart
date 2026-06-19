/// Resultado de una proyección lineal hacia una meta financiera.
class PlanProjection {
  /// Monto objetivo de la meta.
  final double targetAmount;

  /// Valor actual del portafolio o ahorro.
  final double currentAmount;

  /// Fecha límite de la meta.
  final DateTime targetDate;

  /// Meses restantes entre la fecha de referencia y la meta (mínimo 1).
  final int monthsRemaining;

  /// Ahorro mensual necesario para alcanzar la meta con proyección lineal.
  final double requiredMonthlySavings;

  /// Monto proyectado en la fecha objetivo (lineal, sin rendimientos).
  final double projectedAmountAtDate;

  /// Indica si la contribución mensual actual alcanza la meta.
  final bool onTrack;

  /// Contribución mensual usada en la proyección, si se proporcionó.
  final double? monthlyContribution;

  const PlanProjection({
    required this.targetAmount,
    required this.currentAmount,
    required this.targetDate,
    required this.monthsRemaining,
    required this.requiredMonthlySavings,
    required this.projectedAmountAtDate,
    required this.onTrack,
    this.monthlyContribution,
  });
}

/// Hito intermedio en el camino hacia la meta.
class PlanMilestone {
  /// Etiqueta del hito (p. ej. "25%").
  final String label;

  /// Monto acumulado objetivo en este hito.
  final double amount;

  /// Fecha estimada para alcanzar el monto del hito.
  final DateTime targetDate;

  const PlanMilestone({
    required this.label,
    required this.amount,
    required this.targetDate,
  });
}

/// Calculadora determinista de proyecciones lineales para metas financieras.
abstract final class PlanProjectionCalculator {
  static const _milestoneFractions = [0.25, 0.50, 0.75, 1.0];
  static const _milestoneLabels = ['25%', '50%', '75%', '100%'];

  /// Proyección lineal simple (sin rendimientos compuestos — solo ilustrativa).
  ///
  /// [monthsRemaining] = meses entre [asOf] y [targetDate] (mínimo 1).
  /// Si [monthlyContribution] se proporciona:
  /// `projectedAmountAtDate = current + monthly * months`.
  /// `requiredMonthlySavings = max(0, (target - current) / months)`.
  /// `onTrack = projectedAmountAtDate >= targetAmount`.
  static PlanProjection compute({
    required double targetAmount,
    required double currentAmount,
    required DateTime targetDate,
    DateTime? asOf,
    double? monthlyContribution,
  }) {
    final reference = asOf ?? DateTime.now();
    final months = _monthsBetween(reference, targetDate);
    final requiredMonthly = _requiredMonthlySavings(
      targetAmount: targetAmount,
      currentAmount: currentAmount,
      months: months,
    );

    final projected =
        monthlyContribution != null
            ? currentAmount + monthlyContribution * months
            : currentAmount;

    final onTrack =
        monthlyContribution != null
            ? projected >= targetAmount
            : currentAmount >= targetAmount;

    return PlanProjection(
      targetAmount: targetAmount,
      currentAmount: currentAmount,
      targetDate: targetDate,
      monthsRemaining: months,
      requiredMonthlySavings: requiredMonthly,
      projectedAmountAtDate: projected,
      onTrack: onTrack,
      monthlyContribution: monthlyContribution,
    );
  }

  /// Genera 4 hitos al 25/50/75/100% del objetivo con interpolación lineal de fechas.
  static List<PlanMilestone> milestones({
    required PlanProjection projection,
    DateTime? asOf,
  }) {
    final start = asOf ?? DateTime.now();
    final totalMs = projection.targetDate.difference(start).inMilliseconds;
    final milestones = <PlanMilestone>[];

    for (var i = 0; i < _milestoneFractions.length; i++) {
      final fraction = _milestoneFractions[i];
      final amount = projection.targetAmount * fraction;
      final targetDate =
          fraction >= 1.0
              ? projection.targetDate
              : start.add(
                Duration(
                  milliseconds: (totalMs * fraction).round(),
                ),
              );

      milestones.add(
        PlanMilestone(
          label: _milestoneLabels[i],
          amount: amount,
          targetDate: targetDate,
        ),
      );
    }

    return milestones;
  }

  static int _monthsBetween(DateTime start, DateTime end) {
    final months = (end.year - start.year) * 12 + (end.month - start.month);
    if (months < 1) return 1;
    return months;
  }

  static double _requiredMonthlySavings({
    required double targetAmount,
    required double currentAmount,
    required int months,
  }) {
    if (months <= 0) return 0;
    final gap = targetAmount - currentAmount;
    if (gap <= 0) return 0;
    return gap / months;
  }
}
