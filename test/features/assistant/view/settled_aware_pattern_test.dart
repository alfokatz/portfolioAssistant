import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// `PortfolioQaAssistantSurface.build` wraps its `Surface` child in a
// `MediaQuery(disableAnimations: ...)` once that surface has fully
// revealed (see `startFullyRevealed`). This file isolates and proves the
// exact Flutter mechanism that wrap depends on.
//
// Regresión real (causó un crash en producción — `Failed assertion:
// '!_dirty' is not true` en `framework.dart`): la primera versión de ese
// `build()` envolvía `Surface` en `MediaQuery` solo CONDICIONALMENTE
// (`if (widget.startFullyRevealed) surface = MediaQuery(...)`) — un
// cambio de TIPO de widget en el slot hijo de `SurfaceRevealScope` entre
// builds. Flutter reconcilia ese slot por tipo, así que el cambio
// desmonta y vuelve a montar `Surface` entero justo en el instante en que
// termina de revelarse (`onFullyRevealed` → `notifier.markRevealed` →
// rebuild con `startFullyRevealed: true`, sobre la MISMA instancia ya
// montada — un `didUpdateWidget`, no un remount intencional). Una
// variante del mismo bug vivía en `AssistantScreen._settledAware`
// (ya eliminado: las filas del chat ahora reciben un `skipAnimation`
// explícito en `MessageAppearFade`/`TypewriterText`/`FadeSlideIn`, sin
// tocar `MediaQuery` en absoluto). El fix acá: envolver SIEMPRE en el
// mismo tipo de widget y solo cambiar su `data`.
void main() {
  Widget conditionallyWrap(bool alreadyRevealed, Widget child) {
    if (!alreadyRevealed) return child;
    return MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: child,
    );
  }

  Widget alwaysWrap(bool alreadyRevealed, Widget child) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: alreadyRevealed),
      child: child,
    );
  }

  Widget listOf(Widget Function(bool, Widget) settledAware, bool revealed) {
    return MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [settledAware(revealed, const _MountCounter())],
        ),
      ),
    );
  }

  testWidgets(
    'BUG PATTERN: conditionally inserting the MediaQuery ancestor at an '
    'unkeyed list position remounts (loses State) the moment the flag '
    'flips true',
    (tester) async {
      _MountCounterState.mounts = 0;
      await tester.pumpWidget(listOf(conditionallyWrap, false));
      expect(_MountCounterState.mounts, 1);

      await tester.pumpWidget(listOf(conditionallyWrap, true));

      expect(
        _MountCounterState.mounts,
        2,
        reason:
            'the widget type at that list position changed (bare child → '
            'MediaQuery-wrapped child), so Flutter disposed and remounted '
            'it instead of just updating in place',
      );
    },
  );

  testWidgets(
    'FIX: always wrapping in the same MediaQuery type and only toggling '
    'its data preserves State when the flag flips true',
    (tester) async {
      _MountCounterState.mounts = 0;
      await tester.pumpWidget(listOf(alwaysWrap, false));
      expect(_MountCounterState.mounts, 1);

      await tester.pumpWidget(listOf(alwaysWrap, true));

      expect(
        _MountCounterState.mounts,
        1,
        reason:
            'the widget type at that list position stayed MediaQuery the '
            'whole time, so Flutter just updated its data in place — no '
            'dispose, no remount',
      );
    },
  );
}

class _MountCounter extends StatefulWidget {
  const _MountCounter();

  @override
  State<_MountCounter> createState() => _MountCounterState();
}

class _MountCounterState extends State<_MountCounter> {
  static int mounts = 0;

  @override
  void initState() {
    super.initState();
    mounts++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
