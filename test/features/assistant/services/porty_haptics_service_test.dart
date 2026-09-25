import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/reveal_step.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/genui_core/widgets/catalog_component_scope.dart';
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

    test('maps component types to their pattern and ignores unknown ones', () {
      service.componentRevealed('QaTickerMove');
      service.componentRevealed('QaMetricStrip');
      service.componentRevealed('QaTipBanner');
      service.componentRevealed('SomethingElse');
      expect(fired, [
        PortyHapticPattern.heavy,
        PortyHapticPattern.medium,
        PortyHapticPattern.doubleLight,
      ]);
    });

    test('does nothing while disabled', () {
      service.enabled = false;
      service.streamTick();
      service.componentRevealed('QaTickerMove');
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

  group('RevealStep haptics', () {
    late List<PortyHapticPattern> fired;

    Widget harness(SurfaceRevealController controller) {
      fired = [];
      final service = PortyHapticsService(
        enabled: true,
        performer: (p) async => fired.add(p),
      );
      return ProviderScope(
        overrides: [portyHapticsServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          home: SurfaceRevealScope(
            controller: controller,
            child: CatalogComponentScope(
              type: 'QaTickerMove',
              child: RevealStep.fade(
                controller: controller,
                child: const Text('card'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('fires the component pattern once when the reveal finishes', (
      tester,
    ) async {
      await tester.pumpWidget(harness(SurfaceRevealController()));
      expect(fired, isEmpty);
      await tester.pumpAndSettle();
      expect(fired, [PortyHapticPattern.heavy]);

      // Rebuilds no vuelven a vibrar.
      await tester.pumpWidget(harness(SurfaceRevealController()));
      fired.clear();
      await tester.pump();
      expect(fired, isEmpty);
    });

    testWidgets('stays silent when the surface was already revealed', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(SurfaceRevealController(reduceMotion: true)),
      );
      await tester.pumpAndSettle();
      expect(fired, isEmpty);
    });
  });
}
