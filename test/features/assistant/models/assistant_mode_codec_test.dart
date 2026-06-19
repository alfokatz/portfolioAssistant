import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode_codec.dart';

void main() {
  group('AssistantModeCodec.fromQuery', () {
    test('returns portfolio for null', () {
      expect(AssistantModeCodec.fromQuery(null), AssistantMode.portfolio);
    });

    test('returns explore for explore query', () {
      expect(AssistantModeCodec.fromQuery('explore'), AssistantMode.explore);
    });

    test('returns portfolio for invalid query', () {
      expect(AssistantModeCodec.fromQuery('invalid'), AssistantMode.portfolio);
    });
  });

  group('AssistantModeCodec.queryValue round-trip', () {
    for (final mode in AssistantMode.values) {
      test('round-trips ${mode.name}', () {
        expect(AssistantModeCodec.fromQuery(mode.queryValue), mode);
      });
    }
  });
}
