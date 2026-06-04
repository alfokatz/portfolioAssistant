import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/genui_core/genui_surface_ids.dart';
import 'package:portfolio_assistant/features/genui_core/utils/llm_json_sanitizer.dart';

void main() {
  group('LlmJsonSanitizer', () {
    test('extracts JSON from markdown code block', () {
      const raw = '''
Here is the response:
```json
{"version":"v0.9","createSurface":{"surfaceId":"portfolio_analysis"}}
```
''';

      final result = LlmJsonSanitizer.sanitize(raw);
      expect(result, contains('"createSurface"'));
      expect(() => jsonDecode(result.split('\n').first), returnsNormally);
    });

    test('extracts JSON with text before and after', () {
      const raw = '''
Sure! Here you go:
{"version":"v0.9","createSurface":{"surfaceId":"test"}}
Hope that helps!
''';

      final result = LlmJsonSanitizer.sanitize(raw);
      expect(result, contains('"createSurface"'));
    });

    test('preserves two separate A2UI objects', () {
      const raw = '''
{"version":"v0.9","createSurface":{"surfaceId":"portfolio_analysis"}}
{"version":"v0.9","updateComponents":{"surfaceId":"portfolio_analysis","components":[]}}
''';

      final result = LlmJsonSanitizer.sanitize(raw);
      expect(result.split('\n').length, 2);
    });

    test('sanitizeOrFallback returns A2UI fallback for broken JSON', () {
      const raw = 'This is not JSON at all, sorry!';

      final result = LlmJsonSanitizer.sanitizeOrFallback(
        raw,
        surfaceId: GenUiSurfaceIds.portfolioAnalysis,
      );

      expect(result, contains('"createSurface"'));
      expect(result, contains('"updateComponents"'));
      expect(result, contains('"component":"Text"'));
      expect(result, contains('No pude procesar'));
    });

    test('sanitizeOrFallback returns A2UI fallback for empty raw', () {
      final result = LlmJsonSanitizer.sanitizeOrFallback(
        '',
        surfaceId: GenUiSurfaceIds.longTermPlanning,
      );

      expect(result.split('\n').length, 2);
      expect(result, contains('"long_term_planning"'));
    });
  });
}
