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
    testWidgets('shows the thinking orb while streaming with no content yet',
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

      expect(find.byType(AssistantThinkingOrb), findsOneWidget);
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
  });
}
