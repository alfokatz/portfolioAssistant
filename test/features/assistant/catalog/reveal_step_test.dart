import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/reveal_step.dart';

void main() {
  testWidgets('steps unlock in mount order, each waiting for the previous', (
    tester,
  ) async {
    final controller = SurfaceRevealController();
    final activeLog = <String>[];

    Widget stepFor(String label) {
      return RevealStep(
        controller: controller,
        builder: (context, active, onFinished) {
          if (active && !activeLog.contains(label)) {
            activeLog.add(label);
          }
          return active
              ? TextButton(
                onPressed: onFinished,
                child: Text('finish-$label'),
              )
              : SizedBox(key: ValueKey('waiting-$label'));
        },
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [stepFor('a'), stepFor('b'), stepFor('c')],
          ),
        ),
      ),
    );

    // Solo el primer paso está activo al montar.
    expect(activeLog, ['a']);
    expect(find.byKey(const ValueKey('waiting-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('waiting-c')), findsOneWidget);

    await tester.tap(find.text('finish-a'));
    await tester.pump();
    expect(activeLog, ['a', 'b']);
    expect(find.byKey(const ValueKey('waiting-c')), findsOneWidget);

    await tester.tap(find.text('finish-b'));
    await tester.pump();
    expect(activeLog, ['a', 'b', 'c']);
  });

  testWidgets('reduced motion unlocks every step immediately', (
    tester,
  ) async {
    final controller = SurfaceRevealController(reduceMotion: true);
    final activeLog = <String>[];

    Widget stepFor(String label) {
      return RevealStep(
        controller: controller,
        builder: (context, active, onFinished) {
          if (active) activeLog.add(label);
          return const SizedBox();
        },
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(children: [stepFor('a'), stepFor('b'), stepFor('c')]),
        ),
      ),
    );

    expect(activeLog, ['a', 'b', 'c']);
  });

  testWidgets('RevealStep.fade renders reserved-space invisible until active, then fades in', (
    tester,
  ) async {
    final controller = SurfaceRevealController();
    final outer = RevealStep.fade(
      controller: controller,
      child: const Text('primero'),
    );
    // Un segundo paso, detrás de un RevealStep genérico que solo se activa
    // al terminar el primero.
    late VoidCallback finishFirst;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              RevealStep(
                controller: controller,
                builder: (context, active, onFinished) {
                  finishFirst = onFinished;
                  return active
                      ? const Text('paso-activo')
                      : const SizedBox(key: ValueKey('paso-esperando'));
                },
              ),
              outer,
            ],
          ),
        ),
      ),
    );

    // El segundo paso (el fade) todavía no arrancó su animación: el
    // contenido está en el árbol (reserva su espacio) pero invisible.
    final opacityBefore = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacityBefore.opacity, 0);
    expect(find.text('primero'), findsOneWidget);

    finishFirst();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('primero'), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
