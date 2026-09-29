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
              ? TextButton(onPressed: onFinished, child: Text('finish-$label'))
              : SizedBox(key: ValueKey('waiting-$label'));
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

    // Solo el primer paso está activo al montar.
    expect(activeLog, ['a']);
    expect(find.byKey(const ValueKey('waiting-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('waiting-c')), findsOneWidget);

    // Un paso bloqueante (el texto) desbloquea al siguiente recién una
    // pausa después de terminar.
    await tester.tap(find.text('finish-a'));
    await tester.pump();
    expect(activeLog, ['a']);
    await tester.pump(RevealTiming.gapAfterText);
    expect(activeLog, ['a', 'b']);
    expect(find.byKey(const ValueKey('waiting-c')), findsOneWidget);

    await tester.tap(find.text('finish-b'));
    await tester.pump(RevealTiming.gapAfterText);
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

      await tester.pump(RevealTiming.gapAfterText);
      finishB();
      await tester.pump();
      expect(controller.isFullyRevealed, isTrue);
      await tester.pump(RevealTiming.gapAfterText);
    },
  );

  test('isFullyRevealed is false for a controller with no steps at all', () {
    expect(SurfaceRevealController().isFullyRevealed, isFalse);
  });

  testWidgets('reduced motion unlocks every step immediately', (tester) async {
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

  testWidgets('RevealStep.fade stays collapsed until its turn, then opens '
      'its space continuously while it fades in', (tester) async {
    final controller = SurfaceRevealController();
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
                  return const SizedBox(height: 20);
                },
              ),
              RevealStep.fade(
                controller: controller,
                child: const SizedBox(
                  key: ValueKey('card'),
                  height: 200,
                  child: Text('primero'),
                ),
              ),
              const SizedBox(key: ValueKey('below'), height: 10),
            ],
          ),
        ),
      ),
    );

    // Montado (el contenido existe) pero sin ocupar lugar ni verse.
    expect(find.text('primero'), findsOneWidget);
    double belowTop() =>
        tester.getTopLeft(find.byKey(const ValueKey('below'))).dy;
    expect(belowTop(), 20);

    finishFirst();
    await tester.pump(RevealTiming.gapAfterText);

    // Lo de abajo se desliza de a poco: ningún frame salta más de un tramo
    // chico, y llega a su lugar final.
    var previous = belowTop();
    var maxStep = 0.0;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final now = belowTop();
      maxStep = now - previous > maxStep ? now - previous : maxStep;
      previous = now;
    }
    expect(belowTop(), 220);
    expect(maxStep, lessThan(40), reason: 'the space must open, not jump');
    expect(tester.takeException(), isNull);
  });

  testWidgets('widgets enter overlapped: each starts one stagger after the '
      'previous one STARTED, without waiting for it to finish', (tester) async {
    final controller = SurfaceRevealController();
    final started = <String, Duration>{};
    var elapsed = Duration.zero;

    Widget card(String label) => RevealStep.entrance(
      controller: controller,
      builder: (context, active, onFinished) {
        if (active) started.putIfAbsent(label, () => elapsed);
        if (active) onFinished();
        return SizedBox(height: 50, child: Text(label));
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(children: [card('a'), card('b'), card('c')]),
        ),
      ),
    );
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      elapsed += const Duration(milliseconds: 10);
    }

    expect(started.keys, ['a', 'b', 'c']);
    final gapAB = started['b']! - started['a']!;
    final gapBC = started['c']! - started['b']!;
    for (final gap in [gapAB, gapBC]) {
      // ±1 pump de muestreo (10 ms).
      expect(
        gap,
        greaterThanOrEqualTo(
          RevealTiming.stagger - const Duration(milliseconds: 10),
        ),
      );
      expect(gap, lessThan(RevealTiming.entrance));
    }
    expect(controller.isFullyRevealed, isTrue);
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
      await tester.pump(RevealTiming.entrance);
    },
  );

  testWidgets('TwoStageReveal does not crash when mounted active under reduced '
      'motion and onFinished mutates ancestor state synchronously '
      '(regression: setState during build)', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: _MutatingAncestor(
              builder:
                  (context, mutate) => TwoStageReveal(
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
  });
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
