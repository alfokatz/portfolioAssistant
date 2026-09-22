import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/typewriter_text.dart';

void main() {
  testWidgets('reveals the text progressively over time', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TypewriterText(text: 'hola porty', charsPerSecond: 50),
        ),
      ),
    );

    // Recién montado: nada visible todavía.
    expect(find.text('hola porty'), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    final textWidget = tester.widget<Text>(find.byType(Text));
    expect(textWidget.data, isNotEmpty);
    expect(textWidget.data!.length, lessThan('hola porty'.length));

    await tester.pumpAndSettle();
    expect(find.text('hola porty'), findsOneWidget);
  });

  testWidgets('semantics carries the full text immediately, excluding the animated node', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TypewriterText(text: 'texto completo ya', charsPerSecond: 5),
        ),
      ),
    );

    // Sin esperar ni un frame de la animación, el semantics ya tiene todo.
    final semantics = tester.getSemantics(find.byType(TypewriterText));
    expect(semantics.label, 'texto completo ya');
  });

  testWidgets('reduced motion shows the full text instantly and calls onComplete', (
    tester,
  ) async {
    var completed = false;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: TypewriterText(
              text: 'sin animación',
              onComplete: () => completed = true,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('sin animación'), findsOneWidget);
    expect(completed, isTrue);
  });

  testWidgets('onComplete fires once the reveal finishes', (tester) async {
    var completeCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TypewriterText(
            text: 'ok',
            charsPerSecond: 100,
            onComplete: () => completeCount++,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(completeCount, 1);
  });

  testWidgets('does not start until play becomes true', (tester) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TypewriterText(
            text: 'esperando turno',
            charsPerSecond: 100,
            play: false,
            onComplete: () => completed = true,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('esperando turno'), findsNothing);
    expect(completed, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TypewriterText(
            text: 'esperando turno',
            charsPerSecond: 100,
            play: true,
            onComplete: () => completed = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('esperando turno'), findsOneWidget);
    expect(completed, isTrue);
  });
}
