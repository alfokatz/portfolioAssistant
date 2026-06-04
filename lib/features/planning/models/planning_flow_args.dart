/// Argumentos de navegación al flujo de planificación a largo plazo.
class PlanningFlowArgs {
  const PlanningFlowArgs({
    this.initialPrompt,
    this.goalLabel,
    this.targetAmount,
    this.targetDate,
  });

  final String? initialPrompt;
  final String? goalLabel;
  final double? targetAmount;
  final String? targetDate;

  String resolveInitialPrompt() {
    if (initialPrompt != null && initialPrompt!.trim().isNotEmpty) {
      return initialPrompt!.trim();
    }
    if (goalLabel != null && goalLabel!.trim().isNotEmpty) {
      final parts = <String>['Quiero planificar mi meta: ${goalLabel!.trim()}'];
      if (targetAmount != null && targetAmount! > 0) {
        parts.add('con un objetivo de \$${targetAmount!.round()}');
      }
      if (targetDate != null && targetDate!.trim().isNotEmpty) {
        parts.add('para ${targetDate!.trim()}');
      }
      return '${parts.join(' ')}.';
    }
    return 'Quiero planificar mi futuro financiero. ¿Por dónde empezamos?';
  }
}
