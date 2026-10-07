/// Perfil de inversor del usuario: lo completa en Ajustes → Perfil de
/// inversor y lo leen tanto Invertir como Planificar. Es un dato
/// transversal a propósito (no propiedad de un modo), igual que el portfolio.
///
/// El "objetivo" es el TIPO de objetivo, no una meta concreta: el monto y la
/// fecha de una meta puntual siguen viviendo en la meta guardada de
/// Planificar (`PlanGoalSaver`), para no duplicar ese dato.
class InvestorProfile {
  const InvestorProfile({
    required this.risk,
    required this.horizon,
    required this.objective,
    required this.updatedAt,
    this.experience,
    this.drawdownReaction,
  });

  /// Un perfil con más de 12 meses se considera vencido: se sigue usando
  /// (no se borra hasta que el usuario confirme uno nuevo), pero Porty
  /// vuelve a sugerir revisarlo.
  static const staleAfterMonths = 12;

  final RiskTolerance risk;
  final InvestmentHorizon horizon;
  final InvestmentObjective objective;
  final DateTime updatedAt;

  /// Opcional: cuánto sabe de inversiones (ajusta el nivel de explicación).
  final InvestmentExperience? experience;

  /// Opcional: qué haría ante una caída fuerte (el riesgo por
  /// comportamiento, más confiable que la etiqueta que cada uno se pone).
  final DrawdownReaction? drawdownReaction;

  bool isStaleAt(DateTime now) {
    final cutoff = DateTime(
      now.year,
      now.month - staleAfterMonths,
      now.day,
      now.hour,
      now.minute,
    );
    return updatedAt.isBefore(cutoff);
  }
}

enum RiskTolerance {
  conservative('conservative'),
  moderate('moderate'),
  aggressive('aggressive');

  const RiskTolerance(this.storageValue);
  final String storageValue;

  static RiskTolerance? fromStorage(String? value) =>
      values.where((v) => v.storageValue == value).firstOrNull;
}

enum InvestmentHorizon {
  short('short'),
  medium('medium'),
  long('long');

  const InvestmentHorizon(this.storageValue);
  final String storageValue;

  static InvestmentHorizon? fromStorage(String? value) =>
      values.where((v) => v.storageValue == value).firstOrNull;
}

enum InvestmentObjective {
  growth('growth'),
  income('income'),
  preservation('preservation'),
  specificGoal('specific_goal');

  const InvestmentObjective(this.storageValue);
  final String storageValue;

  static InvestmentObjective? fromStorage(String? value) =>
      values.where((v) => v.storageValue == value).firstOrNull;
}

enum InvestmentExperience {
  beginner('beginner'),
  intermediate('intermediate'),
  advanced('advanced');

  const InvestmentExperience(this.storageValue);
  final String storageValue;

  static InvestmentExperience? fromStorage(String? value) =>
      values.where((v) => v.storageValue == value).firstOrNull;
}

/// "Si tu cartera cae 20% en un mes, ¿qué hacés?"
enum DrawdownReaction {
  sell('sell'),
  hold('hold'),
  buyMore('buy_more');

  const DrawdownReaction(this.storageValue);
  final String storageValue;

  static DrawdownReaction? fromStorage(String? value) =>
      values.where((v) => v.storageValue == value).firstOrNull;
}
