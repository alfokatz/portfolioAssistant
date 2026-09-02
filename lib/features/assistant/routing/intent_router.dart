import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';

class ModeSuggestion {
  const ModeSuggestion({required this.suggestedMode, required this.reasonKey});
  final AssistantMode suggestedMode;
  final String reasonKey;
}

abstract final class IntentRouter {
  // Invertir y Planificar viven en una sola pestaña (ver AssistantProvider),
  // así que comparten el mismo set de keywords tanto para sugerir el cambio
  // desde otra pestaña como para elegir el motor interno (resolveInvestPlanEngine).
  static const _investKeywords = [
    'invertir',
    'invert',
    'comprar',
    'presupuesto',
    'budget',
  ];
  static const _planKeywords = [
    'planificar',
    'meta',
    'jubil',
    'ahorrar para',
    'proyección',
  ];

  static ModeSuggestion? suggest({
    required String message,
    required AssistantMode currentMode,
  }) {
    final lower = message.toLowerCase();

    if (currentMode != AssistantMode.invest &&
        currentMode != AssistantMode.plan &&
        (_matchesAny(lower, _investKeywords) ||
            _matchesAny(lower, _planKeywords))) {
      return const ModeSuggestion(
        suggestedMode: AssistantMode.invest,
        reasonKey: 'assistant_mode_suggest_invest',
      );
    }
    if (currentMode != AssistantMode.explore &&
        _matchesAny(lower, [
          'cómo está',
          'como esta',
          'precio de',
          'cotización',
          'ticker',
        ])) {
      return const ModeSuggestion(
        suggestedMode: AssistantMode.explore,
        reasonKey: 'assistant_mode_suggest_explore',
      );
    }
    if (currentMode != AssistantMode.learn &&
        _matchesAny(lower, [
          'qué es',
          'que es',
          'explicame',
          'explicá',
          'significa',
          'diversific',
        ])) {
      return const ModeSuggestion(
        suggestedMode: AssistantMode.learn,
        reasonKey: 'assistant_mode_suggest_learn',
      );
    }
    if (currentMode != AssistantMode.portfolio &&
        _matchesAny(lower, [
          'mi portfolio',
          'mi cartera',
          'mis posiciones',
          'cómo voy',
        ])) {
      return const ModeSuggestion(
        suggestedMode: AssistantMode.portfolio,
        reasonKey: 'assistant_mode_suggest_portfolio',
      );
    }
    return null;
  }

  /// Dentro de la pestaña combinada Invertir+Planificar, elige qué motor
  /// (invest o plan) debe atender el mensaje. Si el mensaje es ambiguo (no
  /// matchea ninguna keyword de ninguno de los dos), continúa con el motor
  /// del turno anterior para no cortar el hilo de la conversación.
  static AssistantMode resolveInvestPlanEngine({
    required String message,
    required AssistantMode lastEngine,
  }) {
    final lower = message.toLowerCase();
    if (_matchesAny(lower, _planKeywords)) return AssistantMode.plan;
    if (_matchesAny(lower, _investKeywords)) return AssistantMode.invest;
    return lastEngine;
  }

  static bool _matchesAny(String text, List<String> keywords) {
    for (final k in keywords) {
      if (text.contains(k)) return true;
    }
    return false;
  }
}
