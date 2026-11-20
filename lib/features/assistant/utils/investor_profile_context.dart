import 'package:portfolio_assistant/domain/entities/investor_profile.dart';

/// Bloque `investor_profile` que reciben los snapshots de Invertir y
/// Planificar. Los valores van en español y listos para citar — mismo
/// criterio que los sectores del snapshot de invest — para que el modelo no
/// tenga que traducir ni reinterpretar nada.
abstract final class InvestorProfileContext {
  static const statusMissing = 'missing';
  static const statusComplete = 'complete';
  static const statusStale = 'stale';

  static Map<String, Object?> build(InvestorProfile? profile, DateTime now) {
    if (profile == null) return {'status': statusMissing};
    return {
      'status': profile.isStaleAt(now) ? statusStale : statusComplete,
      'risk_tolerance': riskLabel(profile.risk),
      'horizon': horizonLabel(profile.horizon),
      'objective': objectiveLabel(profile.objective),
      ..._optional(profile),
      'updated_at': formatDate(profile.updatedAt),
    };
  }

  /// El perfil compacto que va en PORTFOLIO_BRIEF de cada turno (las
  /// instrucciones de cuándo usarlo van en el texto que lo presenta, ver
  /// `AssistantOpenAiService.ask`). Sin perfil, no hay bloque: Porty no
  /// asume nada.
  static Map<String, Object?>? brief(InvestorProfile? profile, DateTime now) {
    if (profile == null) return null;
    return {
      'risk_tolerance': riskLabel(profile.risk),
      'horizon': horizonLabel(profile.horizon),
      'objective': objectiveLabel(profile.objective),
      ..._optional(profile),
      if (profile.isStaleAt(now)) 'stale': true,
    };
  }

  static Map<String, Object?> _optional(InvestorProfile profile) => {
    if (profile.experience != null)
      'experience': experienceLabel(profile.experience!),
    if (profile.drawdownReaction != null)
      'drawdown_reaction': drawdownLabel(profile.drawdownReaction!),
    // Con las palabras del usuario: es lo que más dice de su objetivo real.
    if (profile.notes.isNotEmpty) 'notes': profile.notes,
  };

  static String experienceLabel(InvestmentExperience experience) =>
      switch (experience) {
        InvestmentExperience.beginner => 'principiante',
        InvestmentExperience.intermediate => 'intermedia',
        InvestmentExperience.advanced => 'avanzada',
      };

  static String drawdownLabel(DrawdownReaction reaction) => switch (reaction) {
    DrawdownReaction.sell => 'vendería para no perder más',
    DrawdownReaction.hold => 'esperaría a que se recupere',
    DrawdownReaction.buyMore => 'compraría más aprovechando la baja',
  };

  static String riskLabel(RiskTolerance risk) => switch (risk) {
    RiskTolerance.conservative => 'conservador',
    RiskTolerance.moderate => 'moderado',
    RiskTolerance.aggressive => 'agresivo',
  };

  static String horizonLabel(InvestmentHorizon horizon) => switch (horizon) {
    InvestmentHorizon.short => 'corto plazo (menos de 3 años)',
    InvestmentHorizon.medium => 'mediano plazo (3 a 7 años)',
    InvestmentHorizon.long => 'largo plazo (más de 7 años)',
  };

  static String objectiveLabel(InvestmentObjective objective) =>
      switch (objective) {
        InvestmentObjective.growth => 'hacer crecer el patrimonio',
        InvestmentObjective.income => 'generar ingresos (dividendos)',
        InvestmentObjective.preservation => 'proteger el capital',
        InvestmentObjective.specificGoal => 'juntar para una meta concreta',
      };

  static String formatDate(DateTime date) {
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}
