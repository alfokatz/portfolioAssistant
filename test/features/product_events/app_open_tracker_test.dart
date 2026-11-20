// AppOpenTracker: app_opened al montar y al volver tras >= 30 min, con la
// fuente que anotó cada listener (sin marca, icon).
// Correr: flutter test test/features/product_events/app_open_tracker_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/product_events/providers/app_open_source_provider.dart';
import 'package:portfolio_assistant/features/product_events/view/app_open_tracker.dart';

class _Events extends ProductEvents {
  _Events() : super(client: () => null, prefs: () => null);
  final logged = <(ProductEvent, Map<String, Object?>)>[];

  @override
  void log(ProductEvent event, [Map<String, Object?> props = const {}]) =>
      logged.add((event, props));
}

void main() {
  late _Events events;
  late ProviderContainer container;
  late DateTime now;

  var opens = 0;

  Future<void> pump(WidgetTester tester) async {
    opens = 0;
    events = _Events();
    now = DateTime(2026, 11, 5, 10);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [productEventsProvider.overrideWithValue(events)],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              home: AppOpenTracker(
                clock: () => now,
                onOpen: () => opens++,
                child: const Text('x'),
              ),
            );
          },
        ),
      ),
    );
  }

  const settle = Duration(milliseconds: 1600);

  void lifecycle(WidgetTester tester, AppLifecycleState s) =>
      tester.binding.handleAppLifecycleStateChanged(s);

  testWidgets('mount without marker: icon', (tester) async {
    await pump(tester);
    expect(events.logged, isEmpty); // espera a que los listeners marquen
    await tester.pump(settle);
    expect(events.logged.single.$1, ProductEvent.appOpened);
    expect(events.logged.single.$2, {'source': 'icon'});
  });

  testWidgets('onOpen fires once per counted open', (tester) async {
    await pump(tester);
    await tester.pump(settle);
    expect(opens, 1);
  });

  testWidgets('mount with a marker uses it and clears it', (tester) async {
    await pump(tester);
    container.read(appOpenSourceProvider.notifier).state =
        AppOpenSource.widgetQuestion;
    await tester.pump(settle);
    expect(events.logged.single.$2, {'source': 'widget_question'});
    expect(container.read(appOpenSourceProvider), isNull);
  });

  test('every source has its wire name', () {
    expect(
      {for (final s in AppOpenSource.values) s.wire},
      {'icon', 'widget', 'widget_question', 'push', 'other'},
    );
  });

  testWidgets('resume after 30 min logs again; before, no', (tester) async {
    await pump(tester);
    await tester.pump(settle);
    events.logged.clear();

    lifecycle(tester, AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 10));
    lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump(settle);
    expect(events.logged, isEmpty);

    lifecycle(tester, AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 31));
    container.read(appOpenSourceProvider.notifier).state = AppOpenSource.push;
    lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump(settle);
    expect(events.logged.single.$2, {'source': 'push'});
  });

  testWidgets('a marker from a short resume does not leak to the next one', (
    tester,
  ) async {
    await pump(tester);
    await tester.pump(settle);
    events.logged.clear();

    lifecycle(tester, AppLifecycleState.paused);
    container.read(appOpenSourceProvider.notifier).state = AppOpenSource.widget;
    lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump(settle);
    expect(events.logged, isEmpty);
    expect(container.read(appOpenSourceProvider), isNull);
  });
}
