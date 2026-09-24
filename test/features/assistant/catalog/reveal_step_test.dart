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

  testWidgets(
    'isFullyRevealed only becomes true once the LAST step finishes its own '
    'entrance, not just when it becomes active',
    (tester) async {
      // Regresión: el seguimiento de scroll en la pantalla de chat solía
      // inferir "terminó de crecer" viendo si el alto del contenido dejaba
      // de cambiar por un rato — eso daba falso positivo a mitad de una
      // línea de texto que el typewriter todavía estaba tipeando (el alto
      // no cambia hasta que el texto hace wrap). `isFullyRevealed` es la
      // señal exacta que reemplaza esa heurística: solo se prende cuando el
      // ÚLTIMO paso llama a su propio `onFinished`.
      final controller = SurfaceRevealController();
      late VoidCallback finishA;
      late VoidCallback finishB;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                RevealStep(
                  controller: controller,
                  builder: (context, active, onFinished) {
                    finishA = onFinished;
                    return const SizedBox();
                  },
                ),
                RevealStep(
                  controller: controller,
                  builder: (context, active, onFinished) {
                    finishB = onFinished;
                    return const SizedBox();
                  },
                ),
              ],
            ),
          ),
        ),
      );

      // Ambos slots ya se reclamaron (mismo frame) pero ninguno terminó su
      // propia entrada todavía.
      expect(controller.isFullyRevealed, isFalse);

      finishA();
      await tester.pump();
      // El primer paso terminó, pero el segundo (el último) todavía no —
      // la surface entera sigue sin estar completamente revelada.
      expect(controller.isFullyRevealed, isFalse);

      finishB();
      await tester.pump();
      expect(controller.isFullyRevealed, isTrue);
    },
  );

  test('isFullyRevealed is false for a controller with no steps at all', () {
    expect(SurfaceRevealController().isFullyRevealed, isFalse);
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

  testWidgets(
    'RevealStep.fade does not crash when mounted active under reduced '
    'motion and the controller notification mutates ancestor state '
    'synchronously (regression: setState during build — mirrors '
    'PortfolioQaAssistantSurface listening on SurfaceRevealController)',
    (tester) async {
      final controller = SurfaceRevealController();
      late VoidCallback mutate;
      controller.addListener(() {
        if (controller.isFullyRevealed) mutate();
      });

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: _MutatingAncestor(
                builder: (context, m) {
                  mutate = m;
                  return RevealStep.fade(
                    controller: controller,
                    child: const Text('card'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('card'), findsOneWidget);
    },
  );

  testWidgets(
    'TwoStageReveal does not crash when mounted active under reduced '
    'motion and onFinished mutates ancestor state synchronously '
    '(regression: setState during build)',
    (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: _MutatingAncestor(
                builder: (context, mutate) => TwoStageReveal(
                  active: true,
                  first: const Text('label'),
                  second: const Text('valor'),
                  onFinished: mutate,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('label'), findsOneWidget);
    },
  );
}

/// Ancestro mínimo cuyo `setState()` se dispara desde el `builder` que le
/// pasa el caller — simula el `onFinished` real de `AssistantScreen`, que
/// hace `notifier.markRevealed(...)` sincrónicamente cuando un widget de
/// reveal ya montado revelado dispara su callback durante el build.
class _MutatingAncestor extends StatefulWidget {
  const _MutatingAncestor({required this.builder});

  final Widget Function(BuildContext context, VoidCallback mutate) builder;

  @override
  State<_MutatingAncestor> createState() => _MutatingAncestorState();
}

class _MutatingAncestorState extends State<_MutatingAncestor> {
  @override
  Widget build(BuildContext context) {
    return widget.builder(context, () => setState(() {}));
  }
}
