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

    test('suggests invest (combined tab) when message contains jubilación', () {
      // Invertir y Planificar viven en una sola pestaña ("invest"): una
      // pregunta de planificación también sugiere cambiar a esa pestaña.
      final result = IntentRouter.suggest(
        message: 'Quiero planificar mi jubilación',
        currentMode: AssistantMode.portfolio,
      );

      expect(result?.suggestedMode, AssistantMode.invest);
      expect(result?.reasonKey, 'assistant_mode_suggest_invest');
    });

    test(
      'does not suggest switching when already in the combined invest/plan tab',
      () {
        // Regresión: preguntar algo de planificación ("jubilación") estando
        // ya en la pestaña combinada no debe mostrar el banner de "cambiar a
        // Invertir" — antes esto pasaba porque plan e invest eran pestañas
        // separadas.
        final result = IntentRouter.suggest(
          message: 'para la jubilación en 40 años me podes armar un plan?',
          currentMode: AssistantMode.invest,
        );

        expect(result, isNull);
      },
    );

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

    test(
      'does not suggest learn when "que es" is a coincidental substring',
      () {
        // Regresión: "...considerando que ese ahorro..." contiene "que es"
        // como substring literal (de "que" + "ese"), sin ser una pregunta
        // de "¿qué es X?". Antes esto disparaba la sugerencia de Aprender
        // en medio de una conversación de planificación.
        final result = IntentRouter.suggest(
          message: 'ahi estas considerando que ese ahorro mensual lo '
              'invertiría a una tasa del 10% anual aproximadamente?',
          currentMode: AssistantMode.invest,
        );

        expect(result, isNull);
      },
    );

    test('still suggests learn for a genuine "qué es" question', () {
      final result = IntentRouter.suggest(
        message: '¿Qué es la diversificación?',
        currentMode: AssistantMode.portfolio,
      );

      expect(result?.suggestedMode, AssistantMode.learn);
      expect(result?.reasonKey, 'assistant_mode_suggest_learn');
    });
  });

  group('IntentRouter.resolveInvestPlanEngine', () {
    test('resolves to plan for planning keywords', () {
      final engine = IntentRouter.resolveInvestPlanEngine(
        message: 'para la jubilación en 40 años me podes armar un plan?',
        lastEngine: AssistantMode.invest,
      );

      expect(engine, AssistantMode.plan);
    });

    test('resolves to invest for investment keywords', () {
      final engine = IntentRouter.resolveInvestPlanEngine(
        message: 'Tengo \$500 para invertir',
        lastEngine: AssistantMode.plan,
      );

      expect(engine, AssistantMode.invest);
    });

    test('keeps the previous engine for an ambiguous follow-up', () {
      // Regresión: "En 40 años quiero tener 1 millón de dólares" no matchea
      // ninguna keyword de planificación ni de inversión, pero debe seguir
      // en el motor de plan si el turno anterior estaba ahí.
      final engine = IntentRouter.resolveInvestPlanEngine(
        message: 'En 40 años quiero tener 1 millón de dólares',
        lastEngine: AssistantMode.plan,
      );

      expect(engine, AssistantMode.plan);
    });

    test('prefers plan keywords over invest keywords when both match', () {
      final engine = IntentRouter.resolveInvestPlanEngine(
        message: 'quiero armar un presupuesto para mi jubilación',
        lastEngine: AssistantMode.invest,
      );

      expect(engine, AssistantMode.plan);
    });
  });
}
