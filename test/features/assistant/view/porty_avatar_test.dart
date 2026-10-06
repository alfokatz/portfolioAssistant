import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';

const _brand = PortyAvatarPalette.brand;
const _deg = math.pi / 180;

/// Monta un avatar cuyo estado se cambia con [state].
Future<void> _pump(
  WidgetTester tester,
  ValueNotifier<PortyAvatarState> state, {
  bool animated = true,
  bool entrance = false,
  bool reduceMotion = false,
  bool tickerEnabled = true,
  double size = 72,
  VoidCallback? onTap,
  Key? boundaryKey,
  PortyThinkingStyle thinkingStyle = PortyThinkingStyle.standard,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: TickerMode(
        enabled: tickerEnabled,
        child: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: ValueListenableBuilder<PortyAvatarState>(
              valueListenable: state,
              builder:
                  (_, value, _) => PortyAvatar(
                    state: value,
                    size: size,
                    animated: animated,
                    entrance: entrance,
                    onTap: onTap,
                    thinkingStyle: thinkingStyle,
                  ),
            ),
          ),
        ),
      ),
    ),
  );
}

PortyFrame _frame(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(PortyAvatar),
      matching: find.byType(CustomPaint),
    ),
  );
  return (paint.painter! as PortyAvatarPainter).frame;
}

/// Frames cada [step] (16 ms) durante [duration].
Future<List<PortyFrame>> _record(
  WidgetTester tester,
  Duration duration, {
  int step = 16,
}) async {
  final frames = <PortyFrame>[];
  for (var t = 0; t < duration.inMilliseconds; t += step) {
    await tester.pump(Duration(milliseconds: step));
    frames.add(_frame(tester));
  }
  return frames;
}

/// Hay algo animándose (un ticker pidió frame).
bool _ticking() => SchedulerBinding.instance.transientCallbackCount > 0;

double _max(Iterable<double> v) => v.reduce(math.max);
double _min(Iterable<double> v) => v.reduce(math.min);

void main() {
  setUp(() => PortyAvatar.ambientMotion = true);

  group('drawing (each state shows its own parts)', () {
    final parts = {
      PortyAvatarState.idle: {PortyPart.body, PortyPart.eyes},
      PortyAvatarState.thinking: {
        PortyPart.body,
        PortyPart.eyes,
        PortyPart.spark,
      },
      PortyAvatarState.answering: {
        PortyPart.body,
        PortyPart.eyes,
        PortyPart.mouth,
      },
      PortyAvatarState.answered: {
        PortyPart.body,
        PortyPart.eyes,
        PortyPart.mouth,
      },
      PortyAvatarState.error: {PortyPart.body, PortyPart.eyes, PortyPart.mouth},
    };

    for (final MapEntry(key: state, value: expected) in parts.entries) {
      testWidgets('${state.name}: visible parts and painted pixels', (
        tester,
      ) async {
        final notifier = ValueNotifier(state);
        addTearDown(notifier.dispose);
        const key = Key('avatar');
        // Caja de 72 px = 72 unidades: el punto (x, y) del SVG cae en el
        // píxel (x + 4, y + 4).
        await _pump(tester, notifier, animated: false, boundaryKey: key);

        expect(_frame(tester).visibleParts, expected);

        final pixels = await _Pixels.of(tester, key);
        Color at(double x, double y) => pixels.at(x + 4, y + 4);

        // Boca (centro de la boca de cada estado).
        expect(
          at(33.5, 41.5),
          expected.contains(PortyPart.mouth)
              ? _isColor(_brand.features)
              : _isColor(_brand.body),
        );
        // Destello, arriba a la derecha y fuera del cuerpo.
        expect(
          at(60, 2),
          state == PortyAvatarState.thinking
              ? _isColor(_brand.spark)
              : _isTransparent,
        );
        // Ojos: arriba a la derecha solo al pensar.
        final thinking = state == PortyAvatarState.thinking;
        expect(
          at(33, 25),
          thinking ? _isColor(_brand.features) : _isColor(_brand.body),
        );
        expect(
          at(28, 30),
          thinking ? _isColor(_brand.body) : _isColor(_brand.features),
        );
      });
    }
  });

  group('motion per state', () {
    testWidgets('idle breathes (1 → 1.015, ~3.5 s), blinks every 4–6 s and '
        'glances aside every 8–12 s; the body never moves', (tester) async {
      final state = ValueNotifier(PortyAvatarState.idle);
      addTearDown(state.dispose);
      await _pump(tester, state);

      final frames = await _record(tester, const Duration(seconds: 13));
      final scales = frames.map((f) => f.scale);
      expect(_min(scales), closeTo(1, 0.001));
      expect(_max(scales), closeTo(1.015, 0.001));
      expect(_max(frames.map((f) => f.blink)), greaterThan(0.7));
      expect(
        _max(frames.map((f) => f.eyeOffset.dx.abs())),
        closeTo(PortyAvatarMotion.lookDistance, 0.01),
      );
      expect(frames.every((f) => f.dy == 0 && f.rotation == 0), isTrue);

      // Un parpadeo dura 120 ms: nunca más de 8 frames seguidos cerrando.
      var run = 0;
      var longest = 0;
      for (final f in frames) {
        run = f.blink > 0 ? run + 1 : 0;
        longest = math.max(longest, run);
      }
      expect(longest, inInclusiveRange(1, 8));
    });

    testWidgets('thinking leans ~4°, floats up to ~2 units every 1.6 s and '
        'the spark twinkles', (tester) async {
      final state = ValueNotifier(PortyAvatarState.idle);
      addTearDown(state.dispose);
      await _pump(tester, state);
      state.value = PortyAvatarState.thinking;

      await _record(tester, PortyAvatarMotion.poseBlend);
      final frames = await _record(tester, const Duration(milliseconds: 1600));
      for (final f in frames) {
        expect(f.rotation, closeTo(4 * _deg, 1e-6));
        expect(f.scale, 1);
      }
      expect(_min(frames.map((f) => f.dy)), closeTo(-2.2, 0.05));
      expect(_max(frames.map((f) => f.dy)), closeTo(0, 0.05));
      expect(_min(frames.map((f) => f.sparkGlow)), lessThan(0.4));
      expect(_max(frames.map((f) => f.sparkGlow)), greaterThan(0.95));
    });

    testWidgets('answering moves the mouth every ~0.45 s, with the body back '
        'at the center and breathing', (tester) async {
      final state = ValueNotifier(PortyAvatarState.thinking);
      addTearDown(state.dispose);
      await _pump(tester, state);
      await _record(tester, const Duration(milliseconds: 500));
      state.value = PortyAvatarState.answering;

      await _record(tester, PortyAvatarMotion.poseBlend);
      final frames = await _record(tester, const Duration(milliseconds: 900));
      final mouth = frames.map((f) => f.mouthScale);
      expect(_min(mouth), lessThan(0.5));
      expect(_max(mouth), greaterThan(1.25));
      expect(frames.every((f) => f.rotation == 0 && f.dy == 0), isTrue);
      expect(frames.map((f) => f.scale).toSet().length, greaterThan(1));
    });

    testWidgets('answered hops ~4 units once (350 ms, no bounce) while the '
        'smile is drawn (300 ms)', (tester) async {
      final state = ValueNotifier(PortyAvatarState.answering);
      addTearDown(state.dispose);
      await _pump(tester, state);
      state.value = PortyAvatarState.answered;

      final frames = await _record(tester, const Duration(milliseconds: 600));
      final hop = frames.take(22).map((f) => f.dy).toList();
      expect(_min(hop), closeTo(-PortyAvatarMotion.hopHeight, 0.15));
      // Sube y baja una sola vez: nunca pasa por debajo del reposo.
      expect(hop.every((dy) => dy <= 0), isTrue);
      final peak = hop.indexOf(_min(hop));
      for (var i = 1; i <= peak; i++) {
        expect(hop[i], lessThanOrEqualTo(hop[i - 1]));
      }
      for (var i = peak + 1; i < hop.length; i++) {
        expect(hop[i], greaterThanOrEqualTo(hop[i - 1]));
      }
      expect(frames.skip(22).every((f) => f.dy == 0), isTrue);

      final smile = frames.map((f) => f.smile).toList();
      expect(smile.first, lessThan(0.3));
      expect(smile[19], 1); // 320 ms
    });

    testWidgets('error shakes "no" (±3°, twice, 400 ms) and then stays still '
        'without breathing', (tester) async {
      final state = ValueNotifier(PortyAvatarState.idle);
      addTearDown(state.dispose);
      await _pump(tester, state);
      state.value = PortyAvatarState.error;

      final frames = await _record(tester, const Duration(milliseconds: 420));
      final rotations = frames.map((f) => f.rotation).toList();
      expect(
        _max(rotations.map((r) => r.abs())),
        closeTo(3 * _deg, 0.1 * _deg),
      );
      var signChanges = 0;
      for (var i = 1; i < rotations.length; i++) {
        if (rotations[i].sign * rotations[i - 1].sign < 0) signChanges++;
      }
      expect(signChanges, 3); // + − + −: dos "no"

      await tester.pump(const Duration(milliseconds: 100));
      expect(_frame(tester).bodyAtRest, isTrue);
      expect(_ticking(), isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(_frame(tester).bodyAtRest, isTrue);
    });
  });

  group('transitions', () {
    testWidgets('the face crossfades in 180 ms', (tester) async {
      final state = ValueNotifier(PortyAvatarState.thinking);
      addTearDown(state.dispose);
      await _pump(tester, state);
      state.value = PortyAvatarState.answering;

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 64));
      final mid = _frame(tester);
      expect(mid.from, PortyAvatarState.thinking);
      expect(mid.visibleParts, containsAll([PortyPart.spark, PortyPart.mouth]));

      await tester.pump(const Duration(milliseconds: 140));
      expect(_frame(tester).from, isNull);
      expect(_frame(tester).visibleParts, isNot(contains(PortyPart.spark)));
    });

    testWidgets('the body chains from wherever it was, never jumping', (
      tester,
    ) async {
      final state = ValueNotifier(PortyAvatarState.idle);
      addTearDown(state.dispose);
      await _pump(tester, state);
      final frames = <PortyFrame>[];
      // Cada cambio llega a mitad del movimiento anterior.
      for (final (next, ms) in [
        (PortyAvatarState.thinking, 900),
        (PortyAvatarState.answering, 200),
        (PortyAvatarState.thinking, 700),
        (PortyAvatarState.answered, 150),
        (PortyAvatarState.error, 250),
        (PortyAvatarState.idle, 600),
      ]) {
        state.value = next;
        frames.addAll(
          await _record(tester, Duration(milliseconds: ms), step: 4),
        );
      }
      // Cada 4 ms el movimiento más rápido (el arranque del saltito) avanza
      // ~0,45 u; un corte a mitad de camino sería un salto de hasta ~2 u.
      for (var i = 1; i < frames.length; i++) {
        final a = frames[i - 1];
        final b = frames[i];
        expect((b.dy - a.dy).abs(), lessThan(0.6), reason: 'dy jump at $i');
        expect(
          (b.rotation - a.rotation).abs(),
          lessThan(0.8 * _deg),
          reason: 'rotation jump at $i',
        );
        expect((b.scale - a.scale).abs(), lessThan(0.002));
      }
    });

    testWidgets('no animation changes the size of its box', (tester) async {
      final state = ValueNotifier(PortyAvatarState.idle);
      addTearDown(state.dispose);
      await _pump(tester, state, size: 50, entrance: true, onTap: () {});
      final sizes = <Size>{tester.getSize(find.byType(PortyAvatar))};
      for (final next in [
        PortyAvatarState.thinking,
        PortyAvatarState.answering,
        PortyAvatarState.answered,
        PortyAvatarState.error,
        PortyAvatarState.idle,
      ]) {
        state.value = next;
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          sizes.add(tester.getSize(find.byType(PortyAvatar)));
        }
      }
      await tester.tap(find.byType(PortyAvatar));
      await tester.pump(const Duration(milliseconds: 100));
      sizes.add(tester.getSize(find.byType(PortyAvatar)));
      expect(sizes, {const Size(50, 50)});
    });
  });

  group('chat thinking (pulse)', () {
    const pulse = PortyThinkingStyle.pulse;

    testWidgets('the orb pulse on the body: scale 0.9 → 1.06 and opacity '
        '0.8 → 1 every 3.6 s, an echo of the outline (≤ 0.3, up to 1.35), '
        'eyes up and no spark; the body never moves', (tester) async {
      final state = ValueNotifier(PortyAvatarState.thinking);
      addTearDown(state.dispose);
      await _pump(tester, state, size: 28, thinkingStyle: pulse);

      final frames = await _record(tester, const Duration(milliseconds: 3600));
      final scales = frames.map((f) => f.scale);
      expect(_min(scales), closeTo(0.9, 0.002));
      expect(_max(scales), closeTo(1.06, 0.002));
      final opacity = frames.map((f) => f.bodyOpacity);
      expect(_min(opacity), closeTo(0.8, 0.002));
      expect(_max(opacity), closeTo(1, 0.002));
      // Máximo de escala a mitad de ciclo (la onda del orbe).
      final peak = frames.indexWhere((f) => f.scale == _max(scales));
      expect(peak * 16, closeTo(1800, 40));

      expect(_max(frames.map((f) => f.echoOpacity)), lessThanOrEqualTo(0.3));
      expect(_max(frames.map((f) => f.echoOpacity)), greaterThan(0.2));
      expect(_max(frames.map((f) => f.echoScale)), greaterThan(1.3));
      expect(frames.every((f) => f.dy == 0 && f.rotation == 0), isTrue);
      expect(
        frames.every((f) => !f.visibleParts.contains(PortyPart.spark)),
        isTrue,
      );
      expect(tester.getSize(find.byType(PortyAvatar)), const Size.square(28));
    });

    testWidgets('leaving it, the pulse decelerates to scale 1 and the echo '
        'fades before the face changes (no cut)', (tester) async {
      final state = ValueNotifier(PortyAvatarState.thinking);
      addTearDown(state.dispose);
      await _pump(tester, state, size: 28, thinkingStyle: pulse);
      await _record(tester, const Duration(milliseconds: 1000));
      state.value = PortyAvatarState.answering;

      final frames = await _record(
        tester,
        const Duration(milliseconds: 700),
        step: 4,
      );
      final settling = frames.takeWhile(
        (f) => f.state == PortyAvatarState.thinking,
      );
      // Sigue pensando ~320 ms mientras se asienta.
      expect(settling.length * 4, closeTo(320, 12));
      for (var i = 1; i < frames.length; i++) {
        expect((frames[i].scale - frames[i - 1].scale).abs(), lessThan(0.01));
      }
      final handoff = frames[settling.length];
      expect(handoff.state, PortyAvatarState.answering);
      expect(handoff.scale, closeTo(1, 0.005));
      expect(handoff.bodyOpacity, closeTo(1, 0.005));
      expect(handoff.echoOpacity, 0);
    });

    testWidgets('with reduce motion: eyes up, no pulse, no echo', (
      tester,
    ) async {
      final state = ValueNotifier(PortyAvatarState.thinking);
      addTearDown(state.dispose);
      await _pump(
        tester,
        state,
        size: 28,
        thinkingStyle: pulse,
        reduceMotion: true,
      );
      expect(
        _frame(tester),
        const PortyFrame.still(PortyAvatarState.thinking, spark: false),
      );
      expect(_ticking(), isFalse);
      state.value = PortyAvatarState.answering;
      await tester.pump();
      expect(
        _frame(tester),
        const PortyFrame.still(PortyAvatarState.answering, spark: false),
      );
    });
  });

  group('reduce motion, pausing and static avatars', () {
    testWidgets('with disableAnimations only the expression changes', (
      tester,
    ) async {
      final state = ValueNotifier(PortyAvatarState.idle);
      addTearDown(state.dispose);
      var taps = 0;
      await _pump(
        tester,
        state,
        reduceMotion: true,
        entrance: true,
        onTap: () => taps++,
      );
      for (final next in [...PortyAvatarState.values, PortyAvatarState.idle]) {
        state.value = next;
        await tester.pump();
        expect(_frame(tester), PortyFrame.still(next));
        expect(_ticking(), isFalse);
        await tester.pump(const Duration(seconds: 1));
        expect(_frame(tester), PortyFrame.still(next));
      }
      await tester.tap(find.byType(PortyAvatar));
      await tester.pump();
      expect(taps, 1);
      expect(_frame(tester), const PortyFrame.still(PortyAvatarState.idle));
      expect(_ticking(), isFalse);
    });

    testWidgets('pauses in background and resumes where it was', (
      tester,
    ) async {
      final state = ValueNotifier(PortyAvatarState.thinking);
      addTearDown(state.dispose);
      await _pump(tester, state);
      await _record(tester, const Duration(milliseconds: 700));
      expect(_ticking(), isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final frozen = _frame(tester);
      expect(_ticking(), isFalse);
      await tester.pump(const Duration(seconds: 5));
      expect(_frame(tester), frozen);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_ticking(), isTrue);
      await tester.pump(const Duration(milliseconds: 16));
      // Sigue desde donde quedó (16 ms después), no desde otro punto.
      expect((_frame(tester).dy - frozen.dy).abs(), lessThan(0.2));
    });

    testWidgets('pauses while its screen is hidden (TickerMode off)', (
      tester,
    ) async {
      final state = ValueNotifier(PortyAvatarState.idle);
      addTearDown(state.dispose);
      await _pump(tester, state);
      expect(_ticking(), isTrue);
      await _pump(tester, state, tickerEnabled: false);
      expect(_ticking(), isFalse);
      await _pump(tester, state);
      expect(_ticking(), isTrue);
    });

    testWidgets('a static avatar (chat messages, cards) never animates', (
      tester,
    ) async {
      final state = ValueNotifier(PortyAvatarState.idle);
      addTearDown(state.dispose);
      await _pump(tester, state, animated: false);
      for (final next in PortyAvatarState.values) {
        state.value = next;
        await tester.pump();
        expect(_frame(tester), PortyFrame.still(next));
        expect(_ticking(), isFalse);
      }
    });
  });

  group('interaction and entrance', () {
    testWidgets('a tap looks toward it and hops, then calls onTap', (
      tester,
    ) async {
      final state = ValueNotifier(PortyAvatarState.idle);
      addTearDown(state.dispose);
      var taps = 0;
      PortyAvatar.ambientMotion = false;
      await _pump(tester, state, onTap: () => taps++);
      await tester.pumpAndSettle();

      final box = tester.getRect(find.byType(PortyAvatar));
      await tester.tapAt(box.centerRight - const Offset(4, 0));
      expect(taps, 1);
      final frames = await _record(tester, const Duration(milliseconds: 300));
      expect(_max(frames.map((f) => f.eyeOffset.dx)), greaterThan(2));
      expect(_min(frames.map((f) => f.dy)), lessThan(-2.5));

      await tester.pumpAndSettle();
      expect(_frame(tester), const PortyFrame.still(PortyAvatarState.idle));
    });

    testWidgets('enters with fade + 0.9 → 1 in 300 ms, then blinks', (
      tester,
    ) async {
      final state = ValueNotifier(PortyAvatarState.idle);
      addTearDown(state.dispose);
      PortyAvatar.ambientMotion = false;
      await _pump(tester, state, entrance: true);

      final first = _frame(tester);
      expect(first.opacity, 0);
      expect(first.scale, closeTo(0.9, 1e-9));
      final frames = await _record(tester, const Duration(milliseconds: 500));
      final atEnd = frames[18]; // 304 ms
      expect(atEnd.opacity, 1);
      expect(atEnd.scale, 1);
      expect(frames.skip(18).any((f) => f.blink > 0.5), isTrue);
      expect(frames.take(18).every((f) => f.blink == 0), isTrue);
    });
  });
}

class _Pixels {
  _Pixels(this._bytes, this._width);

  final ByteData _bytes;
  final int _width;

  static Future<_Pixels> of(WidgetTester tester, Key key) async {
    final boundary =
        tester.renderObject(find.byKey(key)) as RenderRepaintBoundary;
    late _Pixels pixels;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData();
      pixels = _Pixels(bytes!, image.width);
      image.dispose();
    });
    return pixels;
  }

  Color at(double x, double y) {
    // El píxel cuyo centro está más cerca de (x, y).
    final offset = (y.floor() * _width + x.floor()) * 4;
    return Color.fromARGB(
      _bytes.getUint8(offset + 3),
      _bytes.getUint8(offset),
      _bytes.getUint8(offset + 1),
      _bytes.getUint8(offset + 2),
    );
  }
}

Matcher _isColor(Color expected) => predicate<Color>((c) {
  int ch(double v) => (v * 255).round();
  return (ch(c.r) - ch(expected.r)).abs() <= 8 &&
      (ch(c.g) - ch(expected.g)).abs() <= 8 &&
      (ch(c.b) - ch(expected.b)).abs() <= 8 &&
      ch(c.a) >= 247;
}, 'is ${expected.toARGB32().toRadixString(16)}');

final Matcher _isTransparent = predicate<Color>(
  (c) => c.a < 0.03,
  'is transparent',
);
