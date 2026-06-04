/// Validación defensiva de enums que GPT-4o puede enviar mal formados.
abstract final class PlanningEnumParser {
  static String milestoneStatus(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'completed':
      case 'completado':
        return 'completed';
      case 'current':
      case 'actual':
        return 'current';
      default:
        return 'upcoming';
    }
  }

  static String impact(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'high':
      case 'alto':
        return 'high';
      case 'low':
      case 'bajo':
        return 'low';
      default:
        return 'medium';
    }
  }

  static String effort(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'easy':
      case 'facil':
      case 'fácil':
        return 'easy';
      case 'hard':
      case 'dificil':
      case 'difícil':
        return 'hard';
      default:
        return 'moderate';
    }
  }

  static String scenarioLabel(String? raw) {
    final normalized = raw?.trim();
    if (normalized == null || normalized.isEmpty) return 'Moderado';
    const valid = {'Conservador', 'Moderado', 'Optimista'};
    if (valid.contains(normalized)) return normalized;
    switch (normalized.toLowerCase()) {
      case 'conservador':
      case 'conservative':
        return 'Conservador';
      case 'optimista':
      case 'optimistic':
        return 'Optimista';
      default:
        return 'Moderado';
    }
  }
}
