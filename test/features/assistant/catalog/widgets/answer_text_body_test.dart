import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/answer_text_body.dart';

void main() {
  group('AnswerTextFormat.normalize', () {
    // La respuesta de las capturas: un solo bloque de corrido.
    const block =
        'Tu cartera combina un ETF amplio del mercado estadounidense, acciones '
        'individuales y SGOV. La mayor concentración está en VOO, MSFT y GOOGL; '
        'eso puede impulsar el crecimiento. En el último año, MSFT, GOOGL y '
        'AAPL subieron, mientras DUOL cayó con fuerza. SGOV se mantuvo casi '
        'estable. Para nuevas inversiones, podrías explorar mercados fuera de '
        'EE. UU. o clases de activos distintas.';

    test('a long block becomes paragraphs of two sentences', () {
      final paragraphs = AnswerTextFormat.normalize(block).split('\n\n');
      expect(paragraphs, hasLength(3));
      expect(paragraphs.first, startsWith('Tu cartera combina'));
      expect(paragraphs.first, endsWith('impulsar el crecimiento.'));
      // "EE. UU." no es un fin de oración.
      expect(paragraphs.last, contains('fuera de EE. UU. o clases'));
    });

    test(
      'short texts, texts with line breaks and numbers stay as they are',
      () {
        expect(
          AnswerTextFormat.normalize('Subió 2 %. Bajó 1 %.'),
          'Subió 2 %. Bajó 1 %.',
        );
        const listed = 'Tres ideas:\n• Uno.\n• Dos.';
        expect(AnswerTextFormat.normalize(listed), listed);
        expect(
          AnswerTextFormat.splitSentences(
            'El S&P 500. El dólar subió 1.5 hoy.',
          ),
          ['El S&P 500.', 'El dólar subió 1.5 hoy.'],
        );
      },
    );

    test('markdown bold never shows its asterisks', () {
      expect(
        AnswerTextFormat.normalize('**VOO** es amplio.'),
        'VOO es amplio.',
      );
    });
  });

  test('blocks: paragraphs and "• " / "- " bullets, in order', () {
    expect(
      AnswerTextFormat.blocks(
        'Tu cartera está concentrada.\n• Tecnología: 60 %.\n- Sin bonos.\n\nUna idea: sumar afuera.',
      ),
      const [
        AnswerBlock('Tu cartera está concentrada.', bullet: false),
        AnswerBlock('Tecnología: 60 %.', bullet: true),
        AnswerBlock('Sin bonos.', bullet: true),
        AnswerBlock('Una idea: sumar afuera.', bullet: false),
      ],
    );
  });

  testWidgets('renders each block, also a half-typed text', (tester) async {
    Future<void> pump(String text) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnswerTextBody(text: text, style: const TextStyle()),
        ),
      ),
    );

    await pump('Resumen.\n• Uno.\n• Dos.');
    expect(find.text('Resumen.'), findsOneWidget);
    expect(find.text('Uno.'), findsOneWidget);
    expect(find.text('Dos.'), findsOneWidget);
    expect(find.text('•  '), findsNWidgets(2));

    await pump('Resumen.\n• U');
    expect(find.text('U'), findsOneWidget);
    await pump('');
    expect(tester.takeException(), isNull);
  });
}
