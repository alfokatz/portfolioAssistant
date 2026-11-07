import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_streamed_text_scope.dart';

void main() {
  Future<bool> wasShown(
    WidgetTester tester,
    String? shown,
    String answer,
  ) async {
    late bool result;
    await tester.pumpWidget(
      QaStreamedTextScope(
        text: shown,
        child: Builder(
          builder: (context) {
            result = QaStreamedTextScope.wasShown(context, answer);
            return const SizedBox();
          },
        ),
      ),
    );
    return result;
  }

  testWidgets('only a text the preview already showed skips the typewriter', (
    tester,
  ) async {
    expect(await wasShown(tester, 'Uno.\n\nDos.', 'Dos.'), isTrue);
    expect(
      await wasShown(tester, 'Tu cartera subió.', ' Tu cartera subió. '),
      isTrue,
    );
    // Reescrita después del control de calidad: se tipea de nuevo.
    expect(
      await wasShown(tester, 'Tu cartera subió.', 'Tu cartera bajó.'),
      isFalse,
    );
    // Sin streaming (o sin vista previa): como siempre.
    expect(await wasShown(tester, null, 'Hola.'), isFalse);
    expect(await wasShown(tester, 'Hola.', ''), isFalse);
  });
}
