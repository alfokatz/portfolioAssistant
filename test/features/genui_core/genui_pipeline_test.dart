import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/analysis/catalog/analysis_catalog.dart';
import 'package:portfolio_assistant/features/genui_core/genui_surface_ids.dart';
import 'package:portfolio_assistant/features/genui_core/utils/a2ui_response_normalizer.dart';
import 'package:portfolio_assistant/features/genui_core/utils/llm_json_sanitizer.dart';
import 'package:portfolio_assistant/features/investment/catalog/investment_catalog.dart';
import 'package:portfolio_assistant/features/planning/catalog/planning_catalog.dart';
import '../../helpers/genui_test_helpers.dart';

void main() {
  group('GenUI pipeline (sanitize → normalize → SurfaceController)', () {
    test('analysis portfolio summary fixture activates surface', () {
      final catalog = AnalysisCatalog.build();
      final controller = SurfaceController(catalogs: [catalog]);
      final raw = loadGenuiFixture('analysis_portfolio_summary.json');

      final sanitized = LlmJsonSanitizer.sanitize(raw);
      final normalized = A2uiResponseNormalizer.normalize(
        sanitized,
        surfaceId: GenUiSurfaceIds.portfolioAnalysis,
      );

      dispatchNormalizedA2ui(controller, normalized);

      expect(
        controller.activeSurfaceIds,
        contains(GenUiSurfaceIds.portfolioAnalysis),
      );
      final surface =
          controller.registry.getSurface(GenUiSurfaceIds.portfolioAnalysis);
      expect(surface, isNotNull);
      expect(surface!.components['root']?.type, 'PortfolioSummaryCard');
    });

    test('analysis news week fixture composes column root', () {
      final catalog = AnalysisCatalog.build();
      final controller = SurfaceController(catalogs: [catalog]);
      final raw = loadGenuiFixture('analysis_news_week.json');

      final normalized = A2uiResponseNormalizer.normalize(
        LlmJsonSanitizer.sanitize(raw),
        surfaceId: GenUiSurfaceIds.portfolioAnalysis,
      );

      dispatchNormalizedA2ui(controller, normalized);

      final surface =
          controller.registry.getSurface(GenUiSurfaceIds.portfolioAnalysis)!;
      expect(surface.components['root']?.type, 'Column');
      expect(surface.components.containsKey('highlight'), isTrue);
      expect(surface.components.containsKey('feed'), isTrue);
    });

    test('investment opportunity fixture activates surface', () {
      final catalog = InvestmentCatalog.build();
      final controller = SurfaceController(catalogs: [catalog]);
      final raw = loadGenuiFixture('investment_opportunity.json');

      final normalized = A2uiResponseNormalizer.normalize(
        LlmJsonSanitizer.sanitize(raw),
        surfaceId: GenUiSurfaceIds.investmentDecision,
      );

      dispatchNormalizedA2ui(controller, normalized);

      expect(
        controller.activeSurfaceIds,
        contains(GenUiSurfaceIds.investmentDecision),
      );
      final surface =
          controller.registry.getSurface(GenUiSurfaceIds.investmentDecision)!;
      expect(surface.components['root']?.type, 'InvestmentOpportunityCard');
    });

    test('planning goal projection fixture wraps column root', () {
      final catalog = PlanningCatalog.build();
      final controller = SurfaceController(catalogs: [catalog]);
      final raw = loadGenuiFixture('planning_goal_projection.json');

      final normalized = A2uiResponseNormalizer.normalize(
        LlmJsonSanitizer.sanitize(raw),
        surfaceId: GenUiSurfaceIds.longTermPlanning,
      );

      dispatchNormalizedA2ui(controller, normalized);

      expect(
        controller.activeSurfaceIds,
        contains(GenUiSurfaceIds.longTermPlanning),
      );
      final surface =
          controller.registry.getSurface(GenUiSurfaceIds.longTermPlanning)!;
      expect(surface.components['root']?.type, 'Column');
      expect(surface.components['chart']?.type, 'ProjectionChart');
    });

    test('broken LLM text falls back to valid A2UI surface', () {
      final catalog = AnalysisCatalog.build();
      final controller = SurfaceController(catalogs: [catalog]);

      const broken = 'Lo siento, no puedo responder en JSON ahora mismo.';
      final fallback = LlmJsonSanitizer.sanitizeOrFallback(
        broken,
        surfaceId: GenUiSurfaceIds.portfolioAnalysis,
      );
      final normalized = A2uiResponseNormalizer.normalize(
        fallback,
        surfaceId: GenUiSurfaceIds.portfolioAnalysis,
      );

      dispatchNormalizedA2ui(controller, normalized);

      expect(
        controller.activeSurfaceIds,
        contains(GenUiSurfaceIds.portfolioAnalysis),
      );
      expect(
        controller.registry.getSurface(GenUiSurfaceIds.portfolioAnalysis),
        isNotNull,
      );
    });
  });

  group('GenUI pipeline widget render', () {
    testWidgets('analysis news surface builds in widget tree', (
      WidgetTester tester,
    ) async {
      final catalog = AnalysisCatalog.build();
      final controller = SurfaceController(catalogs: [catalog]);
      final raw = loadGenuiFixture('analysis_news_week.json');
      final normalized = A2uiResponseNormalizer.normalize(
        raw,
        surfaceId: GenUiSurfaceIds.portfolioAnalysis,
      );
      dispatchNormalizedA2ui(controller, normalized);

      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        genuiTestApp(
          child: Surface(
            surfaceContext: controller.contextFor(
              GenUiSurfaceIds.portfolioAnalysis,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Amazon shares'), findsOneWidget);
      expect(find.textContaining('Otras noticias relevantes'), findsOneWidget);
    });
  });
}
