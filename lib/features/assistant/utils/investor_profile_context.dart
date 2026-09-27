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
      'updated_at': _formatDate(profile.updatedAt),
    };
  }

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

  static String _formatDate(DateTime date) {
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}
