import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/routing/intent_router.dart';

void main() {
  group('IntentRouter.suggest', () {
    test('suggests invest when message contains invertir', () {
      final result = IntentRouter.suggest(
        message: 'Quiero invertir en acciones',
        currentMode: AssistantMode.portfolio,
      );

      expect(result?.suggestedMode, AssistantMode.invest);
      expect(result?.reasonKey, 'assistant_mode_suggest_invest');
    });

    test('suggests explore when message contains precio de', () {
      final result = IntentRouter.suggest(
        message: '¿Cuál es el precio de AAPL?',
        currentMode: AssistantMode.portfolio,
      );

      expect(result?.suggestedMode, AssistantMode.explore);
      expect(result?.reasonKey, 'assistant_mode_suggest_explore');
    });

    test('suggests learn when message contains qué es', () {
      final result = IntentRouter.suggest(
        message: '¿Qué es diversificación?',
        currentMode: AssistantMode.portfolio,
      );

      expect(result?.suggestedMode, AssistantMode.learn);
      expect(result?.reasonKey, 'assistant_mode_suggest_learn');
    });

    test('suggests plan when message contains jubilación', () {
      final result = IntentRouter.suggest(
        message: 'Quiero planificar mi jubilación',
        currentMode: AssistantMode.portfolio,
      );

      expect(result?.suggestedMode, AssistantMode.plan);
      expect(result?.reasonKey, 'assistant_mode_suggest_plan');
    });

    test('suggests portfolio when message contains mi cartera', () {
      final result = IntentRouter.suggest(
        message: '¿Cómo va mi cartera?',
        currentMode: AssistantMode.learn,
      );

      expect(result?.suggestedMode, AssistantMode.portfolio);
      expect(result?.reasonKey, 'assistant_mode_suggest_portfolio');
    });

    test('returns null when already in matching mode', () {
      final result = IntentRouter.suggest(
        message: 'Quiero invertir mil pesos',
        currentMode: AssistantMode.invest,
      );

      expect(result, isNull);
    });

    test('returns null when no keywords match', () {
      final result = IntentRouter.suggest(
        message: 'Hola, buenos días',
        currentMode: AssistantMode.portfolio,
      );

      expect(result, isNull);
    });

    test('does not suggest explore for generic como esta phrasing', () {
      final result = IntentRouter.suggest(
        message: '¿Cómo está mi portfolio hoy?',
        currentMode: AssistantMode.portfolio,
      );

      expect(result, isNull);
    });
  });
}
