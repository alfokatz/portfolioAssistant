import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/states/mode_chat_session.dart';

void main() {
  group('ModeChatSession.sanitizeMessages', () {
    test('removes trailing streaming placeholder', () {
      final sanitized = ModeChatSession.sanitizeMessages([
        const PortfolioQaMessage(
          role: PortfolioQaRole.user,
          content: 'Hola',
        ),
        const PortfolioQaMessage(
          role: PortfolioQaRole.assistant,
          isStreaming: true,
        ),
      ]);

      expect(sanitized, hasLength(1));
      expect(sanitized.first.content, 'Hola');
    });

    test('keeps completed conversation intact', () {
      final messages = [
        const PortfolioQaMessage(
          role: PortfolioQaRole.user,
          content: 'AAPL',
        ),
        const PortfolioQaMessage(
          role: PortfolioQaRole.assistant,
          surfaceId: 'assistant_explore_0',
        ),
      ];

      expect(ModeChatSession.sanitizeMessages(messages), messages);
    });
  });
}
