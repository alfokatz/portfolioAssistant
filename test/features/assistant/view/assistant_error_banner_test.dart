import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_error_banner.dart';
import '../../../helpers/genui_test_helpers.dart';

void main() {
  group('AssistantErrorBanner', () {
    // Regresión: la versión anterior usaba `ListTile(trailing:
    // TextButton(...))`, que ponía el texto del error y el botón
    // "Reintentar" lado a lado en la misma fila. "Reintentar" solo (con el
    // padding y tap-target mínimo por defecto de TextButton) ya ocupaba
    // ~140-165px, dejando el texto del error apretado en ~129px de ancho
    // — envolvía en 8-10 líneas angostas e inflaba la card a más de 200px
    // de alto (medido). Apilar texto y botón en filas separadas le da al
    // texto el ancho completo de la card, sin importar el largo del
    // mensaje ni el idioma.
    testWidgets(
      'gives the error text close to the full card width, not squeezed '
      'beside the retry button',
      (tester) async {
        const message =
            'No pudimos obtener una respuesta de la IA. Intentá de nuevo '
            'en unos segundos.';

        await tester.binding.setSurfaceSize(genuiTestViewportSize);
        await tester.pumpWidget(
          genuiTestApp(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AssistantErrorBanner(message: message, onRetry: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        final textBox =
            tester.renderObject(find.text(message)) as RenderBox;
        // Ancho de card disponible en este viewport: 390 - 2*20 (padding
        // horizontal de página) - 2*12 (padding interno) = 326px. El texto
        // debe usar casi todo eso, no quedar apretado a ~129px como con el
        // layout anterior.
        expect(textBox.size.width, greaterThan(300));
      },
    );

    testWidgets('tapping retry invokes onRetry exactly once', (tester) async {
      var tapCount = 0;
      await tester.binding.setSurfaceSize(genuiTestViewportSize);
      await tester.pumpWidget(
        genuiTestApp(
          child: AssistantErrorBanner(
            message: 'algo salió mal',
            onRetry: () => tapCount++,
          ),
        ),
      );

      await tester.tap(find.byType(TextButton));
      await tester.pump();

      expect(tapCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('onRetry null renders a disabled button without throwing', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(genuiTestViewportSize);
      await tester.pumpWidget(
        genuiTestApp(
          child: const AssistantErrorBanner(
            message: 'algo salió mal',
            onRetry: null,
          ),
        ),
      );

      final button = tester.widget<TextButton>(find.byType(TextButton));
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
