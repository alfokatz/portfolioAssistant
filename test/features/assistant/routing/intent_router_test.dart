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

    // Regresión: ninguna de estas dos preguntas contenía ninguna keyword de
    // ningún motor antes de este fix — ambas caían silenciosamente en
    // `lastEngine`. Si el turno anterior no era explore (p. ej. venía de
    // invertir), la pregunta nunca llegaba al snapshot que trae
    // earnings_calendar/news_sources, y el usuario veía el fallback de "no
    // tengo datos" aunque Finnhub sí tuviera la información — no era un
    // problema de datos, era que la pregunta nunca llegaba al motor correcto.
    test('detects explore when message contains noticias', () {
      final engine = IntentRouter.detectEngine(
        message: '¿Qué noticias hay de AAPL en el último mes?',
        lastEngine: AssistantMode.invest,
      );

      expect(engine, AssistantMode.explore);
    });

    test('detects explore when message contains reporta (earnings calendar)', () {
      final engine = IntentRouter.detectEngine(
        message: '¿Cuándo reporta resultados AAPL?',
        lastEngine: AssistantMode.invest,
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
      );

      expect(engine, AssistantMode.plan);
    });

    test('resolves to invest for investment keywords', () {
      final engine = IntentRouter.resolveInvestPlanEngine(
        message: 'Tengo \$500 para invertir',
      );

      expect(engine, AssistantMode.invest);
    });

    test('an invest keyword plus a goal horizon is a projection → plan', () {
      final engine = IntentRouter.resolveInvestPlanEngine(
        message: 'quiero invertir \$1000 en 10 años, ¿cuánto tendría?',
      );

      expect(engine, AssistantMode.plan);
    });

    test('prefers plan keywords over invest keywords when both match', () {
      final engine = IntentRouter.resolveInvestPlanEngine(
        message: 'quiero armar un presupuesto para mi jubilación',
      );

      expect(engine, AssistantMode.plan);
    });
  });

  // Fix del motor pegajoso en Invertir/Planificar: esos motores se deciden
  // solo por el contenido de cada mensaje, nunca heredando el turno
  // anterior (mismo bug que tenía el router principal con Learn).
  group('Invest/Plan are decided from scratch on every message', () {
    const everyEngine = AssistantMode.values;

    AssistantMode route(String message, AssistantMode last) =>
        IntentRouter.detectEngine(message: message, lastEngine: last);

    test(
      'a goal answer (amount + horizon) reaches plan from ANY engine — '
      'replaces the old "keep plan for an ambiguous follow-up" inheritance',
      () {
        for (final message in const [
          'En 40 años quiero tener 1 millón de dólares',
          'quiero llegar a \$50.000 para 2030',
          'me gustaría juntar 200 mil en 15 años',
        ]) {
          for (final last in everyEngine) {
            expect(route(message, last), AssistantMode.plan, reason: '$message (from $last)');
          }
        }
      },
    );

    test('a budget answer reaches invest from ANY engine', () {
      for (final message in const [
        'Tengo \$500',
        '¿y con 1000 dólares?',
        'cuento con unos 2 mil',
      ]) {
        for (final last in everyEngine) {
          expect(route(message, last), AssistantMode.invest, reason: '$message (from $last)');
        }
      }
    });

    test('a message with no signal no longer stays in invest/plan', () {
      for (final last in [AssistantMode.invest, AssistantMode.plan]) {
        for (final message in const [
          'Hola, buenos días',
          'gracias!',
          '¿A cuánto está AAPL?',
        ]) {
          expect(route(message, last), AssistantMode.portfolio, reason: '$message (from $last)');
        }
      }
    });

    test('keyword questions still leave invest/plan for their own engine', () {
      expect(route('¿Qué es un ETF?', AssistantMode.plan), AssistantMode.learn);
      expect(route('¿Cómo va mi cartera?', AssistantMode.invest), AssistantMode.portfolio);
      expect(route('¿Cuál es el precio de AAPL?', AssistantMode.plan), AssistantMode.explore);
    });

    test('money without a budget verb does not hijack other engines', () {
      // "gané más de $1000" es una pregunta de resultados, no un presupuesto.
      expect(route('¿gané más de \$1000?', AssistantMode.portfolio), AssistantMode.portfolio);
      expect(route('¿gané más de \$1000?', AssistantMode.invest), AssistantMode.portfolio);
    });

    test('a plain year is not a goal (no money marker)', () {
      expect(route('¿cómo le fue a NVDA en 2025?', AssistantMode.plan), AssistantMode.portfolio);
      expect(route('¿cómo le fue a NVDA en 2025?', AssistantMode.learn), AssistantMode.learn);
    });

    test('portfolio/learn/explore inheritance is unchanged (out of scope — '
        'replaced by the unified pipeline)', () {
      expect(route('Hola, buenos días', AssistantMode.learn), AssistantMode.learn);
      expect(route('Hola, buenos días', AssistantMode.explore), AssistantMode.explore);
    });
  });
}
