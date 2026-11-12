import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_streamed_text_scope.dart';

void main() {
  int revealed(String? shown, String answer) =>
      QaStreamedTextScope.revealedIn(shown, answer);

  test('the final answer continues from what the preview revealed', () {
    const answer = 'Tu cartera subió en la semana. NVDA fue la que más aportó.';
    expect(revealed('Tu cartera subió', answer), 'Tu cartera subió '.length);
    // Muy poco revelado: igual sigue desde ahí.
    expect(revealed('Tu c', answer), 'Tu c'.length);
    // Todo revelado: no se tipea de nuevo.
    expect(revealed(answer, answer), answer.length);
  });

  test(
    'paragraph breaks may differ between the half text and the final one',
    () {
      const answer = 'Primera idea.\n\nSegunda idea más larga.';
      expect(
        revealed('Primera idea. Segunda', answer),
        'Primera idea.\n\nSegunda '.length,
      );
    },
  );

  test('the quality check dropped a sentence from the beginning: continues '
      'from what matches', () {
    const answer = 'La baja vino por las restricciones a China.';
    expect(
      revealed('NVDA bajó 3,1% hoy. La baja vino por', answer),
      'La baja vino por '.length,
    );
    expect(revealed('Uno.\n\nDos.', 'Dos.'), 'Dos.'.length);
  });

  test('a rewritten answer, or no preview, types from the start', () {
    expect(revealed('Tu cartera subió.', 'Tu cartera bajó.'), 0);
    expect(revealed(null, 'Hola.'), 0);
    expect(revealed('', 'Hola.'), 0);
    expect(revealed('Hola.', ''), 0);
  });
}
