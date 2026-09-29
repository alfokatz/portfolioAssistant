import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/reveal_step.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PortyHapticsService', () {
    late DateTime now;
    late List<PortyHapticPattern> fired;
    late PortyHapticsService service;

    setUp(() {
      now = DateTime(2026);
      fired = [];
      service = PortyHapticsService(
        enabled: true,
        clock: () => now,
        performer: (p) async => fired.add(p),
      );
    });

    test('throttles stream ticks to one per cooldown window', () {
      service.streamTick();
      now = now.add(const Duration(milliseconds: 40));
      service.streamTick();
      now = now.add(const Duration(milliseconds: 40));
      service.streamTick();
      expect(fired, [streamTickPattern]);

      now = now.add(streamTickCooldown);
      service.streamTick();
      expect(fired, [streamTickPattern, streamTickPattern]);
    });

    test('widget entries tick lightly, the close is a distinct pattern and '
        'a text-only answer keeps its single light tap', () {
      service.widgetEntryStarted(index: 0, total: 2);
      service.widgetEntryStarted(index: 1, total: 2);
      service.answerRevealCompleted();
      service.textAnswerRevealed();
      expect(fired, [
        widgetEntryPattern,
        widgetEntryPattern,
        answerCompletePattern,
        textAnswerPattern,
      ]);
      expect(widgetEntryPattern, PortyHapticPattern.light);
      expect(answerCompletePattern, isNot(widgetEntryPattern));
      expect([
        widgetEntryPattern,
        answerCompletePattern,
        textAnswerPattern,
      ], isNot(contains(PortyHapticPattern.heavy)));
    });

    test('caps widget ticks per answer, keeping the first and the last', () {
      for (var i = 0; i < 8; i++) {
        service.widgetEntryStarted(index: i, total: 8);
      }
      expect(fired, hasLength(maxWidgetEntryTicks));
      expect(PortyHapticsService.ticksOnWidget(0, 8), isTrue);
      expect(PortyHapticsService.ticksOnWidget(7, 8), isTrue);
      expect(PortyHapticsService.ticksOnWidget(1, 8), isFalse);
    });

    test('does nothing while disabled', () {
      service.enabled = false;
      service.streamTick();
      service.widgetEntryStarted(index: 0, total: 1);
      service.answerRevealCompleted();
      service.textAnswerRevealed();
      expect(fired, isEmpty);
    });
  });

  group('hapticsEnabledProvider', () {
    Future<ProviderContainer> containerWith(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('defaults to enabled', () async {
      final container = await containerWith({});
      expect(container.read(hapticsEnabledProvider), isTrue);
      expect(container.read(portyHapticsServiceProvider).enabled, isTrue);
    });

    test('persists the toggle and propagates it to the service', () async {
      final container = await containerWith({});
      final service = container.read(portyHapticsServiceProvider);

      await container.read(hapticsEnabledProvider.notifier).setEnabled(false);

      expect(service.enabled, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(settingsHapticsEnabledKey), isFalse);
    });
  });

  group('reveal haptics (SurfaceRevealController)', () {
    late List<PortyHapticPattern> fired;
    late PortyHapticsService service;

    setUp(() {
      fired = [];
      service = PortyHapticsService(
        enabled: true,
        performer: (p) async => fired.add(p),
      );
    });

    /// Una respuesta como la de Porty: el texto (paso bloqueante que
    /// termina al activarse) + [cards] widgets.
    Widget answer(SurfaceRevealController controller, int cards) {
      return MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              RevealStep(
                controller: controller,
                builder: (context, active, onFinished) {
                  if (active) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => onFinished(),
                    );
                  }
                  return const Text('texto');
                },
              ),
              for (var i = 0; i < cards; i++)
                RevealStep.fade(
                  controller: controller,
                  child: SizedBox(height: 80, child: Text('card $i')),
                ),
            ],
          ),
        ),
      );
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    testWidgets('3 widgets: a light tap as each one STARTS entering, then '
        'the close once the last finished', (tester) async {
      final controller = SurfaceRevealController(haptics: service);
      await tester.pumpWidget(answer(controller, 3));

      // El primer toque cae en el mismo frame en que arranca la entrada de
      // la primera card (pausa tras el texto), no al terminar.
      await tester.pump();
      await tester.pump(RevealTiming.gapAfterText);
      expect(fired, [widgetEntryPattern]);

      await settle(tester);
      expect(fired, [
        widgetEntryPattern,
        widgetEntryPattern,
        widgetEntryPattern,
        answerCompletePattern,
      ]);
    });

    testWidgets('many widgets: never more than 4 taps per answer', (
      tester,
    ) async {
      final controller = SurfaceRevealController(haptics: service);
      await tester.pumpWidget(answer(controller, 7));
      await settle(tester);
      expect(fired, hasLength(maxWidgetEntryTicks + 1));
      expect(fired.last, answerCompletePattern);
    });

    testWidgets('text-only answer: only the usual light tap at the end', (
      tester,
    ) async {
      final controller = SurfaceRevealController(haptics: service);
      await tester.pumpWidget(answer(controller, 0));
      await settle(tester);
      expect(fired, [textAnswerPattern]);
    });

    testWidgets('a rebuilt (already revealed) answer does not vibrate', (
      tester,
    ) async {
      final controller = SurfaceRevealController(
        reduceMotion: true,
        haptics: service,
        hapticsMode: RevealHaptics.none,
      );
      await tester.pumpWidget(answer(controller, 3));
      await settle(tester);
      expect(fired, isEmpty);
    });

    testWidgets('reduce motion: no per-widget taps, only the close', (
      tester,
    ) async {
      final controller = SurfaceRevealController(
        reduceMotion: true,
        haptics: service,
        hapticsMode: RevealHaptics.closeOnly,
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: answer(controller, 3),
        ),
      );
      await settle(tester);
      expect(fired, [answerCompletePattern]);
    });

    testWidgets('the app haptics setting off silences the whole reveal', (
      tester,
    ) async {
      service.enabled = false;
      final controller = SurfaceRevealController(haptics: service);
      await tester.pumpWidget(answer(controller, 3));
      await settle(tester);
      expect(fired, isEmpty);
    });
  });
}
