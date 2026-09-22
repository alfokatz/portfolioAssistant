import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';

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


  static final _whatIsPattern = RegExp(r'(?:qué|que) es\b');

  /// Clasifica el mensaje y decide qué motor debe atenderlo, sin pestañas
  /// visibles ni confirmación del usuario. Si no matchea ninguna keyword de
  /// ningún dominio, sigue con `lastEngine` para no cortar el hilo de la
  /// conversación en curso.
  static AssistantMode detectEngine({
    required String message,
    required AssistantMode lastEngine,
  }) {
    final lower = message.toLowerCase();

    if (_matchesAny(lower, _investKeywords) ||
        _matchesAny(lower, _planKeywords)) {
      return resolveInvestPlanEngine(message: message, lastEngine: lastEngine);
    }
    // Las keywords de portfolio son frases específicas y poco ambiguas
    // ("mi portfolio", "mi cartera"...) — se chequean antes que el patrón
    // genérico de "aprender" (`_whatIsPattern`), que matchea cualquier
    // "qué es" dentro de la oración (p. ej. "¿qué es lo que tiene mayor
    // riesgo en mi portfolio?" no es una pregunta de definición).
    if (_matchesAny(lower, [
      'mi portfolio',
      'mi cartera',
      'mis posiciones',
      'cómo voy',
    ])) {
      return AssistantMode.portfolio;
    }
    if (_matchesAny(lower, [
      'cómo está',
      'como esta',
      'precio de',
      'cotización',
      'ticker',
    ])) {
      return AssistantMode.explore;
    }
    if (_whatIsPattern.hasMatch(lower) ||
        _matchesAny(lower, ['explicame', 'explicá', 'significa', 'diversific'])) {
      return AssistantMode.learn;
    }
    return lastEngine;
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
