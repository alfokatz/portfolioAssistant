import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';

class ModeSuggestion {
  const ModeSuggestion({required this.suggestedMode, required this.reasonKey});
  final AssistantMode suggestedMode;
  final String reasonKey;
}

abstract final class IntentRouter {
  static ModeSuggestion? suggest({
    required String message,
    required AssistantMode currentMode,
  }) {
    final lower = message.toLowerCase();

    if (currentMode != AssistantMode.invest &&
        _matchesAny(lower, [
          'invertir',
          'invert',
          'comprar',
          'presupuesto',
          'budget',
        ])) {
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
    if (currentMode != AssistantMode.plan &&
        _matchesAny(lower, [
          'planificar',
          'meta',
          'jubil',
          'ahorrar para',
          'proyección',
        ])) {
      return const ModeSuggestion(
        suggestedMode: AssistantMode.plan,
        reasonKey: 'assistant_mode_suggest_plan',
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

  static bool _matchesAny(String text, List<String> keywords) {
    for (final k in keywords) {
      if (text.contains(k)) return true;
    }
    return false;
  }
}
