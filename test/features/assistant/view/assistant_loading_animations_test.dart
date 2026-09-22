import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_thinking_orb.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/portfolio_qa_assistant_surface.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/portfolio_qa_chat_bubble.dart';
import 'package:portfolio_assistant/features/genui_core/utils/a2ui_response_normalizer.dart';
import '../../../helpers/genui_test_helpers.dart';

void main() {
  group('AssistantThinkingOrb', () {
    testWidgets('animates through frames without throwing', (tester) async {
      await tester.pumpWidget(
        genuiTestApp(child: const AssistantThinkingOrb(size: 20)),
      );

      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders a static frame when reduced motion is on', (
      tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: genuiTestApp(child: const AssistantThinkingOrb(size: 20)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(tester.takeException(), isNull);
      expect(find.byType(AssistantThinkingOrb), findsOneWidget);
    });
  });

  group('PortfolioQaChatBubble', () {
    // The streaming placeholder no longer routes through this bubble: the
    // thinking orb now floats directly in the message list (see
    // AssistantScreen._buildMessageTile), chrome-free, instead of being
    // boxed inside a bubble container. This bubble only ever renders text.
    testWidgets('never embeds the thinking orb, even for a streaming message',
        (tester) async {
      await tester.pumpWidget(
        genuiTestApp(
          child: const PortfolioQaChatBubble(
            message: PortfolioQaMessage(
              role: PortfolioQaRole.assistant,
              surfaceId: 'assistant_portfolio_0',
              isStreaming: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AssistantThinkingOrb), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'user message types out progressively and calls onTypingComplete once done',
      (tester) async {
        var completed = false;
        await tester.pumpWidget(
          genuiTestApp(
            child: PortfolioQaChatBubble(
              message: const PortfolioQaMessage(
                role: PortfolioQaRole.user,
                content: 'hola porty, como va mi cartera',
              ),
              onTypingComplete: () => completed = true,
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 100));
        expect(completed, isFalse);
        final partial = tester.widget<Text>(find.byType(Text)).data!;
        expect(partial.length, lessThan('hola porty, como va mi cartera'.length));

        await tester.pumpAndSettle();
        expect(completed, isTrue);
        expect(find.text('hola porty, como va mi cartera'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'does not retype once already revealed and remounted under '
      'disableAnimations',
      (tester) async {
        // Regresión: al igual que PortfolioQaAssistantSurface, la burbuja de
        // usuario vive como item del ListView de la pantalla de chat, que
        // desmonta/remonta items al scrollear. AssistantScreen envuelve la
        // fila entera en `MediaQuery(disableAnimations: true)` (ver
        // `_settledAware`) una vez que `PortfolioQaMessage.hasRevealed` es
        // `true` para ese mensaje — acá se simula ese ciclo directamente
        // sobre TypewriterText/PortfolioQaChatBubble, sin pasar por toda la
        // pantalla.
        const message = PortfolioQaMessage(
          role: PortfolioQaRole.user,
          content: 'hola porty, como va mi cartera',
        );
        var completedCount = 0;

        await tester.pumpWidget(
          genuiTestApp(
            child: PortfolioQaChatBubble(
              message: message,
              onTypingComplete: () => completedCount++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(completedCount, 1);
        expect(find.text(message.content), findsOneWidget);

        // Desmonta — simula el mensaje scrolleando fuera del viewport.
        await tester.pumpWidget(genuiTestApp(child: const SizedBox()));
        await tester.pump();
        expect(find.text(message.content), findsNothing);

        // Remonta bajo `disableAnimations: true` — lo que produce
        // `_settledAware` una vez que el mensaje ya se marcó revelado.
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: genuiTestApp(
              child: PortfolioQaChatBubble(
                message: message,
                onTypingComplete: () => completedCount++,
              ),
            ),
          ),
        );

        // Un solo pump: si el typewriter se hubiera vuelto a disparar, acá
        // solo se vería un prefijo del texto, no el texto completo.
        await tester.pump();
        expect(find.text(message.content), findsOneWidget);
        expect(completedCount, 2);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'reduced motion shows the full user message instantly and still calls onTypingComplete',
      (tester) async {
        var completed = false;
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: genuiTestApp(
              child: PortfolioQaChatBubble(
                message: const PortfolioQaMessage(
                  role: PortfolioQaRole.user,
                  content: 'sin animación',
                ),
                onTypingComplete: () => completed = true,
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.text('sin animación'), findsOneWidget);
        expect(completed, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('PortfolioQaAssistantSurface', () {
    testWidgets('fades in on mount without throwing', (tester) async {
      final controller =
          SurfaceController(catalogs: [PortfolioQaCatalog.build()]);
      const surfaceId = 'portfolio_qa_0';
      const raw = '''
[
  {"id": "root", "component": "QaAnswerText", "text": "Tu portfolio subió 5,4% hoy."}
]
''';
      final normalized =
          A2uiResponseNormalizer.normalize(raw, surfaceId: surfaceId);
      dispatchNormalizedA2ui(controller, normalized);

      await tester.binding.setSurfaceSize(genuiTestViewportSize);
      await tester.pumpWidget(
        genuiTestApp(
          child: PortfolioQaAssistantSurface(
            surfaceId: surfaceId,
            surfaceContext: controller.contextFor(surfaceId),
          ),
        ),
      );

      // Mid-entrance frame, then settled. El texto se revela con typewriter
      // (ver TypewriterText), así que hace falta esperar a que termine, no
      // solo el fade/slide de entrada de la surface.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Tu portfolio subió 5,4% hoy.'), findsOneWidget);
    });

    testWidgets(
      'onFullyRevealed fires once, only after the typewriter finishes '
      '— not on every intermediate frame while it is still growing',
      (tester) async {
        // Regresión: la pantalla de chat solía perseguir el fondo del
        // scroll con una heurística de "el alto del contenido dejó de
        // cambiar por un rato", que daba falso positivo a mitad de una
        // línea de texto que el typewriter todavía estaba revelando.
        // `onFullyRevealed` reemplaza esa heurística por una señal exacta
        // — este test confirma que no dispara antes de tiempo mientras el
        // texto sigue tipeándose, y que sí dispara una sola vez al final.
        final controller =
            SurfaceController(catalogs: [PortfolioQaCatalog.build()]);
        const surfaceId = 'portfolio_qa_0';
        const text = 'Diversificar significa repartir tu inversión entre '
            'distintos activos para no depender del resultado de uno solo.';
        final normalized = A2uiResponseNormalizer.normalize(
          '[{"id": "root", "component": "QaAnswerText", "text": "$text"}]',
          surfaceId: surfaceId,
        );
        dispatchNormalizedA2ui(controller, normalized);

        var revealedCount = 0;
        await tester.binding.setSurfaceSize(genuiTestViewportSize);
        await tester.pumpWidget(
          genuiTestApp(
            child: PortfolioQaAssistantSurface(
              surfaceId: surfaceId,
              surfaceContext: controller.contextFor(surfaceId),
              onFullyRevealed: () => revealedCount++,
            ),
          ),
        );

        // Mid-typewriter: el texto todavía se está revelando de a poco, así
        // que la señal de "surface completa" no debe haber disparado.
        await tester.pump(const Duration(milliseconds: 100));
        expect(revealedCount, 0);

        await tester.pumpAndSettle();
        expect(revealedCount, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'startFullyRevealed shows the final content instantly on remount, '
      'without replaying the typewriter/reveal',
      (tester) async {
        // Regresión: scrollear el historial de chat lejos de un mensaje y
        // de vuelta desmonta y vuelve a montar su `PortfolioQaAssistantSurface`
        // (el `ListView` no mantiene vivos los items fuera de su cache
        // extent). Sin este flag, cada remount reiniciaba el typewriter
        // desde cero — este test simula justo ese ciclo: revelar completo →
        // desmontar (scroll fuera de vista) → remontar (scroll de vuelta)
        // con `startFullyRevealed: true`, y confirma que el segundo montaje
        // no anima nada.
        final controller =
            SurfaceController(catalogs: [PortfolioQaCatalog.build()]);
        const surfaceId = 'portfolio_qa_0';
        const text = 'Tu portfolio subió 5,4% hoy.';
        final normalized = A2uiResponseNormalizer.normalize(
          '[{"id": "root", "component": "QaAnswerText", "text": "$text"}]',
          surfaceId: surfaceId,
        );
        dispatchNormalizedA2ui(controller, normalized);

        await tester.binding.setSurfaceSize(genuiTestViewportSize);

        // 1) Primer montaje: revela completo, como el turno original.
        await tester.pumpWidget(
          genuiTestApp(
            child: PortfolioQaAssistantSurface(
              surfaceId: surfaceId,
              surfaceContext: controller.contextFor(surfaceId),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining(text), findsOneWidget);

        // 2) Desmonta — simula el mensaje scrolleando fuera del viewport.
        await tester.pumpWidget(genuiTestApp(child: const SizedBox()));
        await tester.pump();
        expect(find.textContaining(text), findsNothing);

        // 3) Remonta con `startFullyRevealed: true` — simula el scroll de
        // vuelta, ahora que el modelo ya sabe que este mensaje se reveló.
        await tester.pumpWidget(
          genuiTestApp(
            child: PortfolioQaAssistantSurface(
              surfaceId: surfaceId,
              surfaceContext: controller.contextFor(surfaceId),
              startFullyRevealed: true,
            ),
          ),
        );

        // Un solo pump (no pumpAndSettle): si el typewriter se hubiera
        // vuelto a disparar, acá solo se vería un prefijo del texto, no el
        // texto completo.
        await tester.pump();
        expect(find.textContaining(text), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'renders blank when read through the wrong controller, but correctly '
      'through the one that generated it',
      (tester) async {
        // Regresión: en la pestaña combinada Invertir+Planificar, cada motor
        // (invest/plan) tiene su propio AssistantOpenAiService y por lo tanto
        // su propio SurfaceController. Antes del fix, AssistantScreen siempre
        // resolvía el surface a través del controller de la pestaña visible
        // (invest), así que una respuesta generada por el motor plan
        // aparecía como una burbuja vacía. `message.engineMode` +
        // `AssistantProvider.serviceFor` ahora garantizan que se lea del
        // controller correcto — este test reproduce el bug y prueba el fix
        // a nivel de SurfaceController, sin pasar por la red.
        final displayModeController =
            SurfaceController(catalogs: [PortfolioQaCatalog.build()]);
        final engineController =
            SurfaceController(catalogs: [PortfolioQaCatalog.build()]);
        const surfaceId = 'assistant_invest_0';
        const raw = '''
[
  {"id": "root", "component": "QaAnswerText", "text": "Quiero jubilarme con \$500.000 en 20 años."}
]
''';
        final normalized =
            A2uiResponseNormalizer.normalize(raw, surfaceId: surfaceId);
        // Solo el controller del motor real (plan) recibe la respuesta.
        dispatchNormalizedA2ui(engineController, normalized);

        await tester.binding.setSurfaceSize(genuiTestViewportSize);

        // Bug reproducido: leer con el controller de la pestaña visible.
        await tester.pumpWidget(
          genuiTestApp(
            child: PortfolioQaAssistantSurface(
              surfaceId: surfaceId,
              surfaceContext: displayModeController.contextFor(surfaceId),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.textContaining('jubilarme'),
          findsNothing,
          reason:
              'el controller de la pestaña visible nunca vio este surface',
        );

        // Fix: leer con el controller del motor que efectivamente respondió.
        await tester.pumpWidget(
          genuiTestApp(
            child: PortfolioQaAssistantSurface(
              surfaceId: surfaceId,
              surfaceContext: engineController.contextFor(surfaceId),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.textContaining('jubilarme'), findsOneWidget);
      },
    );
  });
}
