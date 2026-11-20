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

    test('the user bubble ticks lighter than Porty, each with its own '
        'throttle', () {
      service.userTypeTick();
      service.streamTick();
      now = now.add(const Duration(milliseconds: 40));
      service.userTypeTick();
      expect(fired, [userTypeTickPattern, streamTickPattern]);
      expect(userTypeTickPattern, PortyHapticPattern.selection);
      expect(streamTickPattern, PortyHapticPattern.light);

      now = now.add(streamTickCooldown);
      service.userTypeTick();
      expect(fired.last, userTypeTickPattern);
    });

    test('widgets: a firm tap as each one starts, a click as it settles; '
        'the close is firmer still and text-only answers end with a tap '
        'above the word ticks', () {
      service.widgetEntryStarted();
      service.widgetEntrySettled();
      service.answerRevealCompleted();
      service.textAnswerRevealed();
      expect(fired, [
        widgetEntryPattern,
        widgetSettlePattern,
        answerCompletePattern,
        textAnswerPattern,
      ]);
      expect(widgetEntryPattern, PortyHapticPattern.medium);
      expect(widgetSettlePattern, PortyHapticPattern.selection);
      expect(answerCompletePattern, PortyHapticPattern.heavy);
      expect(textAnswerPattern, PortyHapticPattern.medium);
    });

    test('does nothing while disabled', () {
      service.enabled = false;
      service.streamTick();
      service.userTypeTick();
      service.widgetEntryStarted();
      service.widgetEntrySettled();
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

    testWidgets('3 widgets: a tap as each one STARTS entering, a click as '
        'it settles, and the close instead of the last click', (tester) async {
      final controller = SurfaceRevealController(haptics: service);
      await tester.pumpWidget(answer(controller, 3));

      // El primer toque cae en el mismo frame en que arranca la entrada de
      // la primera card (pausa tras el texto), no al terminar.
      await tester.pump();
      await tester.pump(RevealTiming.gapAfterText);
      expect(fired, [widgetEntryPattern]);

      await settle(tester);
      // Escalonadas (160 ms) y cada entrada dura 460 ms: las tres arrancan
      // antes de que la primera se asiente.
      expect(fired, [
        widgetEntryPattern,
        widgetEntryPattern,
        widgetEntryPattern,
        widgetSettlePattern,
        widgetSettlePattern,
        answerCompletePattern,
      ]);
    });

    testWidgets('many widgets: every one taps and settles', (tester) async {
      final controller = SurfaceRevealController(haptics: service);
      await tester.pumpWidget(answer(controller, 7));
      await settle(tester);
      expect(fired.where((p) => p == widgetEntryPattern), hasLength(7));
      expect(fired.where((p) => p == widgetSettlePattern), hasLength(6));
      expect(fired.last, answerCompletePattern);
    });

    testWidgets('text-only answer: only the tap at the end', (
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
