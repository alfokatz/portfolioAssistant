import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/fade_slide_in.dart';

void main() {
  testWidgets(
    'does not replay its entrance once already shown and remounted under '
    'disableAnimations',
    (tester) async {
      // Regresión: FadeSlideIn se usa para el saludo inicial + chips de
      // sugerencia dentro del ListView de la pantalla de chat, que puede
      // desmontar y volver a montar esos items al scrollear (ver
      // AssistantScreen._settledAware + AssistantState.introRevealed). Una
      // vez que la cascada ya se mostró, el remonte debe saltar directo al
      // estado final, no volver a animar — acá se aísla el mecanismo
      // (MediaQuery.disableAnimationsOf) sin levantar toda la pantalla.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: FadeSlideIn(child: Text('hola')))),
      );

      // Dispara el `Future.delayed(widget.delay, ...)` con delay cero (hace
      // falta un primer `pump` con tiempo para que el timer corra) y deja
      // avanzar la animación a mitad de camino.
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 50));
      final midOpacity = tester.widget<Opacity>(find.byType(Opacity)).opacity;
      expect(midOpacity, greaterThan(0));
      expect(midOpacity, lessThan(1));

      // Desmonta — simula scrollear el saludo fuera del viewport.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      await tester.pump();

      // Remonta ya "revelado" — como haría `_settledAware` una vez que
      // `AssistantState.introRevealed` es `true`.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: FadeSlideIn(child: Text('hola')),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
