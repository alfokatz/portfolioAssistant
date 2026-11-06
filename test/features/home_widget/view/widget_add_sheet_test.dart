// WidgetAddSheet: vista previa con datos reales o ilustrativa, "Agregar" en
// Android (pin soportado / no soportado) y en iOS (pasos), "Ahora no" y la
// hoja directa en pasos con un widget ya instalado; claro y oscuro, 375.
// Correr: flutter test test/features/home_widget/view/widget_add_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/home_widget/data/home_widget_store.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_add_sheet.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

import '../home_widget_test_helpers.dart';

class _Events extends ProductEvents {
  _Events() : super(client: () => null, prefs: () => null);
  final logged = <(ProductEvent, Map<String, Object?>)>[];

  @override
  void log(ProductEvent event, [Map<String, Object?> props = const {}]) =>
      logged.add((event, props));

  List<ProductEvent> get names => [for (final e in logged) e.$1];
}

Map<String, Object?> _ready() => {
  'state': 'ready',
  'change_pct_text': '+1,0%',
  'direction': 'up',
  'phrase': 'Tu cartera sube hoy.',
  'period': 'today',
  'labels': {'period_today': 'Hoy'},
  'v2': {
    'labels': {'your_portfolio': 'tu cartera'},
  },
};

void main() {
  late _Events events;
  late FakeHomeWidgetStore store;

  Future<void> open(
    WidgetTester tester, {
    required String platform,
    bool dark = false,
    bool installed = false,
    WidgetPromptSource source = WidgetPromptSource.auto,
    Map<String, Object?>? snapshot,
  }) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    events = _Events();
    store =
        FakeHomeWidgetStore()
          ..platformName = platform
          ..snapshotJson = snapshot;
    final probe = ProviderContainer();
    final theme =
        dark
            ? probe.read(themeDataDarkProvider)
            : probe.read(themeDataLightProvider);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeWidgetStoreProvider.overrideWithValue(store),
          productEventsProvider.overrideWithValue(events),
        ],
        child: MaterialApp(
          theme: theme,
          home: Consumer(
            builder:
                (context, ref, _) => Scaffold(
                  body: TextButton(
                    onPressed:
                        () => WidgetAddSheet.show(
                          context,
                          ref,
                          source: source,
                          installed: installed,
                        ),
                    child: const Text('open'),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('preview uses the real snapshot ($mode)', (tester) async {
      await open(tester, platform: 'ios', dark: dark, snapshot: _ready());
      expect(find.text('home_widget_add_title'), findsOneWidget);
      expect(find.text('tu cartera'), findsOneWidget);
      expect(find.text('Tu cartera sube hoy.'), findsOneWidget);
      expect(find.text('home_widget_add_confirm'), findsOneWidget);
      expect(find.text('home_widget_add_later'), findsOneWidget);
      expect(events.names, [ProductEvent.widgetPromptShown]);
      expect(events.logged.single.$2, {'source': 'auto'});
      expect(tester.takeException(), isNull);
    });

    testWidgets('iOS: Agregar shows numbered steps, no pin ($mode)', (
      tester,
    ) async {
      await open(tester, platform: 'ios', dark: dark, snapshot: _ready());
      await tester.tap(find.text('home_widget_add_confirm'));
      await tester.pumpAndSettle();
      for (var i = 1; i <= 5; i++) {
        expect(find.text('home_widget_add_steps_ios_$i'), findsOneWidget);
      }
      expect(find.text('home_widget_add_manual_note'), findsNothing);
      expect(store.pinRequests, 0);
      expect(events.logged.last.$1, ProductEvent.widgetPromptAddTapped);
      expect(events.logged.last.$2, {'platform': 'ios', 'method': 'steps'});
      await tester.tap(find.text('home_widget_add_done'));
      await tester.pumpAndSettle();
      // Tocó Agregar: cerrar los pasos no es "Ahora no".
      expect(events.names, isNot(contains(ProductEvent.widgetPromptDismissed)));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no snapshot: illustrative preview without numbers', (
    tester,
  ) async {
    await open(tester, platform: 'ios');
    expect(find.text('home_widget_add_preview_sample'), findsOneWidget);
    expect(find.text('home_widget_hidden_amount'), findsOneWidget);
  });

  testWidgets('Android with pin support asks the launcher and closes', (
    tester,
  ) async {
    await open(tester, platform: 'android', snapshot: _ready());
    await tester.tap(find.text('home_widget_add_confirm'));
    await tester.pumpAndSettle();
    expect(store.pinRequests, 1);
    expect(find.text('home_widget_add_title'), findsNothing);
    expect(events.logged.last.$2, {'platform': 'android', 'method': 'pin'});
    expect(events.names, isNot(contains(ProductEvent.widgetPromptDismissed)));
  });

  testWidgets('Android without pin support shows the manual steps', (
    tester,
  ) async {
    await open(tester, platform: 'android', snapshot: _ready());
    store.pinSupported = false;
    await tester.tap(find.text('home_widget_add_confirm'));
    await tester.pumpAndSettle();
    expect(store.pinRequests, 0);
    expect(find.text('home_widget_add_manual_note'), findsOneWidget);
    for (var i = 1; i <= 4; i++) {
      expect(find.text('home_widget_add_steps_android_$i'), findsOneWidget);
    }
    expect(events.logged.last.$2, {'platform': 'android', 'method': 'steps'});
  });

  testWidgets('Android pin that throws falls back to the steps', (
    tester,
  ) async {
    await open(tester, platform: 'android', snapshot: _ready());
    store.failPin = true;
    await tester.tap(find.text('home_widget_add_confirm'));
    await tester.pumpAndSettle();
    expect(find.text('home_widget_add_steps_android_1'), findsOneWidget);
  });

  testWidgets('Ahora no logs the dismissal', (tester) async {
    await open(tester, platform: 'ios', snapshot: _ready());
    await tester.tap(find.text('home_widget_add_later'));
    await tester.pumpAndSettle();
    expect(events.names.last, ProductEvent.widgetPromptDismissed);
    expect(events.logged.last.$2, {'source': 'auto'});
  });

  testWidgets('swiping it away also counts as dismissed', (tester) async {
    await open(tester, platform: 'ios', snapshot: _ready());
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('home_widget_add_title'), findsNothing);
    expect(events.names.last, ProductEvent.widgetPromptDismissed);
  });

  testWidgets('already installed (settings): opens on the steps', (
    tester,
  ) async {
    await open(
      tester,
      platform: 'ios',
      installed: true,
      source: WidgetPromptSource.settings,
    );
    expect(find.text('home_widget_add_steps_more_title'), findsOneWidget);
    expect(find.text('home_widget_add_steps_ios_1'), findsOneWidget);
    expect(find.text('home_widget_add_confirm'), findsNothing);
    expect(events.logged.single.$2, {'source': 'settings'});
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(events.names, [ProductEvent.widgetPromptShown]);
  });
}
