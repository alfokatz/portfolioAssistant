import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog.dart';
import 'package:portfolio_assistant/features/genui_core/utils/a2ui_response_normalizer.dart';
import 'package:portfolio_assistant/features/genui_core/utils/llm_json_sanitizer.dart';
import '../../helpers/genui_test_helpers.dart';

void main() {
  group('GenUI pipeline (sanitize → normalize → SurfaceController)', () {
    test('portfolio Q&A answer fixture activates surface', () {
      final catalog = PortfolioQaCatalog.build();
      final controller = SurfaceController(catalogs: [catalog]);
      const surfaceId = 'portfolio_qa_0';
      const raw = '''
{"version":"v0.9","createSurface":{"surfaceId":"$surfaceId","catalogId":"https://a2ui.org/specification/v0_9/standard_catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"$surfaceId","components":[
  {"id":"answer","component":"QaAnswerText","text":"Tu portfolio subió 5,4% hoy."}
]}}
''';

      final sanitized = LlmJsonSanitizer.sanitize(raw);
      final normalized = A2uiResponseNormalizer.normalize(
        sanitized,
        surfaceId: surfaceId,
      );

      dispatchNormalizedA2ui(controller, normalized);

      expect(controller.activeSurfaceIds, contains(surfaceId));
      final surface = controller.registry.getSurface(surfaceId);
      expect(surface, isNotNull);
      expect(surface!.components['answer']?.type, 'QaAnswerText');
    });

    test('broken LLM text falls back to valid A2UI surface', () {
      final catalog = PortfolioQaCatalog.build();
      final controller = SurfaceController(catalogs: [catalog]);
      const surfaceId = 'portfolio_qa_0';

      const broken = 'Lo siento, no puedo responder en JSON ahora mismo.';
      final fallback = LlmJsonSanitizer.sanitizeOrFallback(
        broken,
        surfaceId: surfaceId,
      );
      final normalized = A2uiResponseNormalizer.normalize(
        fallback,
        surfaceId: surfaceId,
      );

      dispatchNormalizedA2ui(controller, normalized);

      expect(controller.activeSurfaceIds, contains(surfaceId));
      expect(controller.registry.getSurface(surfaceId), isNotNull);
    });
  });

  group('GenUI pipeline widget render', () {
    testWidgets('portfolio Q&A answer surface builds in widget tree', (
      WidgetTester tester,
    ) async {
      final catalog = PortfolioQaCatalog.build();
      final controller = SurfaceController(catalogs: [catalog]);
      const surfaceId = 'portfolio_qa_0';
      const raw = '''
{"version":"v0.9","createSurface":{"surfaceId":"$surfaceId","catalogId":"https://a2ui.org/specification/v0_9/standard_catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"$surfaceId","components":[
  {"id":"answer","component":"QaAnswerText","text":"Tu portfolio subió 5,4% hoy."}
]}}
''';
      final normalized = A2uiResponseNormalizer.normalize(
        raw,
        surfaceId: surfaceId,
      );
      dispatchNormalizedA2ui(controller, normalized);

      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        genuiTestApp(
          child: Surface(
            surfaceContext: controller.contextFor(surfaceId),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Tu portfolio subió 5,4% hoy.'), findsOneWidget);
    });
  });
}
