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
{"version":"v0.9","createSurface":{"surfaceId":"portfolioSummary","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
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
{"version":"v0.9","createSurface":{"surfaceId":"portfolioSummary","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
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
{"version":"v0.9","createSurface":{"surfaceId":"long_term_planning","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
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

    test(
      'adds createSurface when a new surface only gets updateComponents '
      '(what the model does after a tool round)',
      () {
        const raw =
            '{"version":"v0.9","updateComponents":{"surfaceId":"x",'
            '"components":[{"id":"root","component":"Column","children":[]}]}}';

        final added = A2uiResponseNormalizer.normalize(
          raw,
          surfaceId: 'assistant_3',
          ensureCreateSurface: true,
        );
        expect(added.split('\n').first, contains('"createSurface"'));
        expect(added, contains('"surfaceId":"assistant_3"'));

        final untouched = A2uiResponseNormalizer.normalize(
          raw,
          surfaceId: 'assistant_3',
        );
        expect(untouched, isNot(contains('"createSurface"')));
      },
    );
    // Regresión: "¿qué posiciones cerré?" terminaba en "No pude procesar tu
    // consulta" porque el modelo juntaba dos operaciones en un objeto y
    // A2uiMessage.fromJson tiraba A2uiValidationError fuera del retry.
    const merged = '''
{"version":"v0.9",
 "createSurface":{"surfaceId":"s","catalogId":"c"},
 "updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"QaAnswerText","text":"Hola"}]}}
''';

    test('splits a message carrying two operations into one per line', () {
      final lines = A2uiResponseNormalizer.normalize(
        merged,
        surfaceId: 'turn_1',
      ).split('\n');

      expect(lines, hasLength(2));
      expect(lines[0], contains('"createSurface"'));
      expect(lines[0], isNot(contains('"updateComponents"')));
      expect(lines[1], contains('"updateComponents"'));
      expect(lines[1], contains('"surfaceId":"turn_1"'));
    });

    test('drops createSurface when the surface already exists', () {
      final normalized = A2uiResponseNormalizer.normalize(
        merged,
        surfaceId: 'turn_1',
        stripCreateSurface: true,
      );

      expect(normalized, isNot(contains('"createSurface"')));
      expect(normalized, contains('"updateComponents"'));
    });
  });
}
