import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/genui_core/genui_surface_ids.dart';
import 'package:portfolio_assistant/features/genui_core/utils/a2ui_response_normalizer.dart';

void main() {
  group('A2uiResponseNormalizer', () {
    test('wraps bare component array into createSurface + updateComponents', () {
      const raw = '''
[
  {
    "id": "root",
    "component": "PortfolioSummaryCard",
    "totalValue": 1000,
    "totalGainLoss": 50,
    "totalGainLossPercent": 5,
    "trend": "up",
    "periodLabel": "hoy"
  }
]
''';

      final normalized = A2uiResponseNormalizer.normalize(
        raw,
        surfaceId: GenUiSurfaceIds.portfolioAnalysis,
      );

      expect(normalized, contains('"createSurface"'));
      expect(normalized, contains('"updateComponents"'));
      expect(normalized, contains('"surfaceId":"portfolio_analysis"'));
      expect(normalized, contains('"PortfolioSummaryCard"'));
    });

    test('rewrites wrong surfaceId to portfolio_analysis', () {
      const raw = '''
{"version":"v0.9","createSurface":{"surfaceId":"portfolioSummary","catalogId":"https://a2ui.org/specification/v0_9/standard_catalog.json"}}
''';

      final normalized = A2uiResponseNormalizer.normalize(
        raw,
        surfaceId: GenUiSurfaceIds.portfolioAnalysis,
      );

      expect(normalized, contains('"surfaceId":"portfolio_analysis"'));
      expect(normalized, isNot(contains('portfolioSummary')));
    });

    test('adds updateComponents when createSurface exists without components', () {
      const raw = '''
{"version":"v0.9","createSurface":{"surfaceId":"portfolioSummary","catalogId":"https://a2ui.org/specification/v0_9/standard_catalog.json"}}
[
  {"id":"summary","component":"PortfolioSummaryCard","totalValue":1,"totalGainLoss":1,"totalGainLossPercent":1,"trend":"up","periodLabel":"hoy"}
]
''';

      final normalized = A2uiResponseNormalizer.normalize(
        raw,
        surfaceId: GenUiSurfaceIds.portfolioAnalysis,
      );

      expect(normalized.split('\n').length, greaterThanOrEqualTo(2));
      expect(normalized, contains('"updateComponents"'));
      expect(normalized, contains('"id":"root"'));
      expect(normalized, contains('"component":"Column"'));
    });

    test('wraps updateComponents without root Column into Column root', () {
      const raw = '''
{"version":"v0.9","createSurface":{"surfaceId":"long_term_planning","catalogId":"https://a2ui.org/specification/v0_9/standard_catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"long_term_planning","components":[
  {"id":"goal","component":"GoalCard","goalLabel":"Retiro","targetAmount":500000,"targetDate":"2046-01-01","currentProgress":10,"currentSaved":50000,"monthsRemaining":240},
  {"id":"chart","component":"ProjectionChart","currentValue":50000,"targetValue":500000,"targetDate":"2046-01-01","highlightScenario":"Moderado","scenarios":[
    {"label":"Conservador","color":"#8B95A8","projectedValue":400000,"monthlyRequired":800},
    {"label":"Moderado","color":"#2979FF","projectedValue":500000,"monthlyRequired":620},
    {"label":"Optimista","color":"#00C853","projectedValue":580000,"monthlyRequired":480}
  ]}
]}}
''';

      final normalized = A2uiResponseNormalizer.normalize(
        raw,
        surfaceId: GenUiSurfaceIds.longTermPlanning,
      );

      expect(normalized, contains('"id":"root"'));
      expect(normalized, contains('"component":"Column"'));
      expect(normalized, contains('"children":["goal","chart"]'));
    });
  });
}
