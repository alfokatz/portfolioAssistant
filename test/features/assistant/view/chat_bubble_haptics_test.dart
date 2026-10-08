import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/portfolio_qa_chat_bubble.dart';

void main() {
  late List<PortyHapticPattern> fired;

  Future<void> pump(WidgetTester tester, PortfolioQaMessage message) async {
    fired = [];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portyHapticsServiceProvider.overrideWithValue(
            PortyHapticsService(
              enabled: true,
              performer: (p) async => fired.add(p),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: PortfolioQaChatBubble(message: message)),
        ),
      ),
    );
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  const text = '¿Cómo viene mi cartera esta semana comparada con el mercado?';

  testWidgets('the user message ticks lightly while it is written in the '
      'bubble', (tester) async {
    await pump(
      tester,
      const PortfolioQaMessage(role: PortfolioQaRole.user, content: text),
    );
    expect(fired, isNotEmpty);
    expect(fired.toSet(), {userTypeTickPattern});
  });

  testWidgets('an already revealed message does not vibrate', (tester) async {
    await pump(
      tester,
      const PortfolioQaMessage(
        role: PortfolioQaRole.user,
        content: text,
        hasRevealed: true,
      ),
    );
    expect(fired, isEmpty);
  });
}
