import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';

/// Cargando → listo, como el análisis de una empresa al llegar los datos.
Widget _app({required bool ready, required bool reduceMotion}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(
      body: Column(
        children: [
          QaStateSwitcher(
            child:
                ready
                    ? const SizedBox(
                      key: ValueKey('ready'),
                      height: 300,
                      child: Text('Análisis'),
                    )
                    : const SizedBox(
                      key: ValueKey('loading'),
                      height: 80,
                      child: Text('Cargando'),
                    ),
          ),
        ],
      ),
    ),
  ),
);

void main() {
  for (final reduceMotion in [true, false]) {
    testWidgets('changing state never throws (reduce motion: $reduceMotion)', (
      tester,
    ) async {
      await tester.pumpWidget(_app(ready: false, reduceMotion: reduceMotion));
      await tester.pumpWidget(_app(ready: true, reduceMotion: reduceMotion));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Análisis'), findsOneWidget);
      expect(tester.getSize(find.byType(QaStateSwitcher)).height, 300);
    });
  }

  testWidgets('with reduce motion the new state is final on the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(_app(ready: false, reduceMotion: true));
    await tester.pumpWidget(_app(ready: true, reduceMotion: true));
    expect(tester.getSize(find.byType(QaStateSwitcher)).height, 300);
    expect(find.text('Cargando'), findsNothing);
  });
}
