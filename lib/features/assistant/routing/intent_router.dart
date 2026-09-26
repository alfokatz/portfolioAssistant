import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/modes/plan/goal_extractor.dart';

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

  /// Motor por defecto cuando un mensaje no da ninguna señal de dominio y
  /// el turno anterior fue de Invertir/Planificar — mismo default que
  /// `AssistantArgs.initialMode`.
  static const _defaultEngine = AssistantMode.portfolio;

  /// Un monto con marca explícita de dinero ("\$500", "1 millón", "50 mil",
  /// "200 dólares"). Un número suelto ("2025", "3") no cuenta.
  static final _moneyPattern = RegExp(
    r'\$\s*\d|\d[\d.,]*\s*(?:mil\b|mill[oó]n|k\b|usd\b|u\$s|d[oó]lares|pesos)',
    caseSensitive: false,
  );

  /// Presupuesto disponible: "tengo \$500", "¿y con 1000 dólares?", "cuento
  /// con 2 mil" — la respuesta típica a "¿cuánto querés invertir?".
  static final _budgetPattern = RegExp(
    r'\b(?:tengo|con|dispongo de|cuento con)\s+(?:unos?\s+|alrededor de\s+)?'
    r'(?:\$\s*\d|\d[\d.,]*\s*(?:mil\b|mill[oó]n|k\b|usd\b|u\$s|d[oó]lares|pesos))',
    caseSensitive: false,
  );

  /// Meta financiera: un monto + un horizonte ("en 40 años quiero tener 1
  /// millón", "\$50.000 para 2030") — la respuesta típica a "¿cuál es tu
  /// meta?". Reusa el parser de fechas del contexto de Plan.
  static bool _hasGoalSignal(String message) =>
      _moneyPattern.hasMatch(message) &&
      GoalExtractor.extractTargetDate(message) != null;

  static bool _hasBudgetSignal(String message) =>
      _budgetPattern.hasMatch(message);

  /// Clasifica el mensaje y decide qué motor debe atenderlo, sin pestañas
  /// visibles ni confirmación del usuario.
  ///
  /// Invertir/Planificar se deciden SOLO por el contenido del mensaje
  /// (keywords, o señales de meta/presupuesto), nunca heredando el motor
  /// del turno anterior: antes, una vez en esos motores, cualquier mensaje
  /// sin keywords ("hola", "¿a cuánto está AAPL?") se quedaba ahí — el
  /// mismo bug de motor pegajoso que tenía el router principal.
  ///
  /// Para portfolio/learn/explore, un mensaje sin señales todavía sigue con
  /// `lastEngine`: ese ruteo lo reemplaza el pipeline unificado (ver la
  /// decisión de unificar modos), así que no se toca acá.
  static AssistantMode detectEngine({
    required String message,
    required AssistantMode lastEngine,
  }) {
    final lower = message.toLowerCase();

    if (_matchesAny(lower, _investKeywords) ||
        _matchesAny(lower, _planKeywords)) {
      return resolveInvestPlanEngine(message: message);
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
      // Calendario de resultados y noticias por ticker (ver
      // explore_prompt_rules.dart) viven en este motor, pero "¿qué
      // noticias hay de AAPL?" / "¿cuándo reporta resultados NVDA?" no
      // contienen ninguna de las keywords de arriba — sin esto, esas
      // preguntas nunca llegaban a explore y el usuario veía un fallback
      // de "no tengo datos" aunque Finnhub sí tuviera la información.
      'noticias',
      'reporta',
      'calendario de resultados',
      'próximo reporte',
      'último reporte',
    ])) {
      return AssistantMode.explore;
    }
    if (_whatIsPattern.hasMatch(lower) ||
        _matchesAny(lower, ['explicame', 'explicá', 'significa', 'diversific'])) {
      return AssistantMode.learn;
    }
    // Señales de contenido, sin keyword: evaluadas recién acá para no
    // cambiar el ruteo de ningún mensaje que ya matcheaba otro dominio.
    if (_hasGoalSignal(message)) return AssistantMode.plan;
    if (_hasBudgetSignal(message)) return AssistantMode.invest;
    if (lastEngine == AssistantMode.invest || lastEngine == AssistantMode.plan) {
      return _defaultEngine;
    }
    return lastEngine;
  }

  /// Para un mensaje que ya matcheó alguna keyword de Invertir/Planificar,
  /// elige entre ambos motores solo por contenido: plan si hay keyword de
  /// planificación o una meta con horizonte ("quiero invertir \$1000 en 10
  /// años" es una proyección), invest en cualquier otro caso.
  static AssistantMode resolveInvestPlanEngine({required String message}) {
    final lower = message.toLowerCase();
    if (_matchesAny(lower, _planKeywords) || _hasGoalSignal(message)) {
      return AssistantMode.plan;
    }
    return AssistantMode.invest;
  }

  static bool _matchesAny(String text, List<String> keywords) {
    for (final k in keywords) {
      if (text.contains(k)) return true;
    }
    return false;
  }
}
