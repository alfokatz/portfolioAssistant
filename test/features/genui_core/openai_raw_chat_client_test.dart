import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_raw_chat_client.dart';

void main() {
  group('extractResponsesOutputText', () {
    test('extracts output_text from message items', () {
      final text = OpenAIRawChatClient.extractResponsesOutputText({
        'output': [
          {
            'type': 'web_search_call',
            'status': 'completed',
          },
          {
            'type': 'message',
            'content': [
              {
                'type': 'output_text',
                'text': 'Apple reportó ganancias sólidas.',
              },
            ],
          },
        ],
      });

      expect(text, contains('Apple reportó ganancias sólidas'));
    });

    test('prefers top-level output_text when present', () {
      final text = OpenAIRawChatClient.extractResponsesOutputText({
        'output_text': 'Resumen directo',
        'output': [],
      });

      expect(text, 'Resumen directo');
    });

    test('includes web search source urls', () {
      final text = OpenAIRawChatClient.extractResponsesOutputText({
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': 'Noticia principal'},
            ],
          },
          {
            'type': 'web_search_call',
            'action': {
              'sources': [
                {'type': 'url', 'url': 'https://reuters.com/aapl'},
              ],
            },
          },
        ],
      });

      expect(text, contains('Noticia principal'));
      expect(text, contains('https://reuters.com/aapl'));
    });
  });
}
