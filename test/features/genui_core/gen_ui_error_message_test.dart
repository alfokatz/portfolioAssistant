import 'package:dart_openai/dart_openai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';

void main() {
  group('genUiErrorMessage', () {
    test('429 without rate limit text is treated as rate limit', () {
      final error = RequestFailedException(
        '{"error":{"message":"Too many requests"}}',
        429,
      );

      expect(isOpenAiRateLimitError(error), isTrue);
      expect(
        genUiErrorMessage(error),
        contains('límite de uso por minuto'),
      );
    });

    test('extracts retry seconds from retry-after milliseconds', () {
      expect(
        openAiSuggestedRetrySeconds('retry-after: 3200ms'),
        4,
      );
    });
  });
}
