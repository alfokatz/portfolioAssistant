import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/streaming_typewriter.dart';

void main() {
  Widget app(
    String text, {
    List<String>? revealed,
    VoidCallback? onWord,
    bool reducedMotion = false,
  }) => MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: MaterialApp(
      home: Scaffold(
        body: StreamingTypewriter(
          text: text,
          charsPerSecond: 20,
          onRevealed: revealed?.add,
          onWordRevealed: onWord,
          builder: (context, visible) => Text(visible),
        ),
      ),
    ),
  );

  String shown(WidgetTester tester) =>
      tester.widget<Text>(find.byType(Text)).data!;

  testWidgets('types what arrived word by word and, when more text arrives, '
      'continues instead of starting over', (tester) async {
    final revealed = <String>[];
    var words = 0;
    await tester.pumpWidget(
      app('Tu cartera', revealed: revealed, onWord: () => words++),
    );
    expect(shown(tester), '');

    await tester.pump(const Duration(milliseconds: 250)); // ~5 caracteres
    final partial = shown(tester);
    expect(partial, isNotEmpty);
    expect('Tu cartera'.startsWith(partial), isTrue);
    expect(partial.length, lessThan('Tu cartera'.length));

    // Llega más texto: sigue desde donde iba, sin volver a cero.
    await tester.pumpWidget(
      app('Tu cartera subió hoy.', revealed: revealed, onWord: () => words++),
    );
    expect(shown(tester).length, greaterThanOrEqualTo(partial.length));

    for (var i = 0; i < 125; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(shown(tester), 'Tu cartera subió hoy.');
    expect(revealed.last, 'Tu cartera subió hoy.');
    expect(words, greaterThanOrEqualTo(3));

    // Alcanzó lo recibido: espera sin hacer nada.
    await tester.pump(const Duration(seconds: 1));
    expect(shown(tester), 'Tu cartera subió hoy.');
  });

  testWidgets('reduced motion shows everything that arrived at once', (
    tester,
  ) async {
    final revealed = <String>[];
    await tester.pumpWidget(
      app('Hola.', revealed: revealed, reducedMotion: true),
    );
    expect(shown(tester), 'Hola.');
    expect(revealed.last, 'Hola.');
  });

  testWidgets('semantics carries everything received', (tester) async {
    await tester.pumpWidget(app('Texto recibido'));
    expect(
      tester.getSemantics(find.byType(StreamingTypewriter)).label,
      'Texto recibido',
    );
  });
}
