import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/routing/intent_router.dart';

void main() {
  group('IntentRouter.detectEngine', () {
    test('detects invest when message contains invertir', () {
      final engine = IntentRouter.detectEngine(
        message: 'Quiero invertir en acciones',
        lastEngine: AssistantMode.portfolio,
      );

      expect(engine, AssistantMode.invest);
    });

    test('detects explore when message contains precio de', () {
      final engine = IntentRouter.detectEngine(
        message: '¿Cuál es el precio de AAPL?',
        lastEngine: AssistantMode.portfolio,
      );

      expect(engine, AssistantMode.explore);
    });

    test('detects learn when message contains qué es', () {
      final engine = IntentRouter.detectEngine(
        message: '¿Qué es diversificación?',
        lastEngine: AssistantMode.portfolio,
      );

      expect(engine, AssistantMode.learn);
    });

    test('detects plan when message contains jubilación', () {
      // Invertir y Planificar comparten detección (ver AssistantProvider):
      // una pregunta de planificación resuelve directamente al motor plan.
      final engine = IntentRouter.detectEngine(
        message: 'Quiero planificar mi jubilación',
        lastEngine: AssistantMode.portfolio,
      );

      expect(engine, AssistantMode.plan);
    });

    test(
      'keeps resolving to plan when already answering with that engine',
      () {
        final engine = IntentRouter.detectEngine(
          message: 'para la jubilación en 40 años me podes armar un plan?',
          lastEngine: AssistantMode.invest,
        );

        expect(engine, AssistantMode.plan);
      },
    );

    test('detects portfolio when message contains mi cartera', () {
      final engine = IntentRouter.detectEngine(
        message: '¿Cómo va mi cartera?',
        lastEngine: AssistantMode.learn,
      );

      expect(engine, AssistantMode.portfolio);
    });

    test('detects invest when already answering with that engine', () {
      final engine = IntentRouter.detectEngine(
        message: 'Quiero invertir mil pesos',
        lastEngine: AssistantMode.invest,
      );

      expect(engine, AssistantMode.invest);
    });

    test('keeps the last engine when no keywords match', () {
      final engine = IntentRouter.detectEngine(
        message: 'Hola, buenos días',
        lastEngine: AssistantMode.portfolio,
      );

      expect(engine, AssistantMode.portfolio);
    });

    test(
      'does not detect learn when "que es" is a coincidental substring',
      () {
        // Regresión: "...considerando que ese ahorro..." contiene "que es"
        // como substring literal (de "que" + "ese"), sin ser una pregunta
        // de "¿qué es X?". Antes esto disparaba erróneamente el motor learn
        // en medio de una conversación de planificación.
        final engine = IntentRouter.detectEngine(
          message: 'ahi estas considerando que ese ahorro mensual lo '
              'invertiría a una tasa del 10% anual aproximadamente?',
          lastEngine: AssistantMode.invest,
        );

        expect(engine, AssistantMode.invest);
      },
    );

    test('still detects learn for a genuine "qué es" question', () {
      final engine = IntentRouter.detectEngine(
        message: '¿Qué es la diversificación?',
        lastEngine: AssistantMode.portfolio,
      );

      expect(engine, AssistantMode.learn);
    });

    test(
      'detects portfolio even when the message also matches the "qué es" pattern',
      () {
        // Regresión: "¿qué es lo que tiene mayor riesgo en mi portfolio?"
        // contiene "qué es" (patrón de aprender) Y "mi portfolio" (keyword
        // explícita de portfolio) — la mención explícita al portfolio debe
        // ganar, porque antes esto se enrutaba a aprender (que no tiene
        // datos del portfolio) y Porty respondía que no podía ver las
        // inversiones del usuario.
        final engine = IntentRouter.detectEngine(
          message:
              'y actualmente en mi Portfolio, que es lo que tiene mayor '
              'riesgo?',
          lastEngine: AssistantMode.learn,
        );

        expect(engine, AssistantMode.portfolio);
      },
    );
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
