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

      // Mid-entrance frame, then settled.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Tu portfolio subió 5,4% hoy.'), findsOneWidget);
    });

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
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull);
        expect(find.textContaining('jubilarme'), findsOneWidget);
      },
    );
  });
}
