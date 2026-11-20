// WidgetAddTile (Ajustes): sin widget invita a sumarlo; con uno instalado lo
// dice y la hoja abre directo en los pasos. Claro y oscuro, 375.
// Correr: flutter test test/features/home_widget/view/widget_add_tile_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/home_widget/data/home_widget_store.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_add_tile.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

import '../home_widget_test_helpers.dart';

class _Events extends ProductEvents {
  _Events() : super(client: () => null, prefs: () => null);
  final logged = <(ProductEvent, Map<String, Object?>)>[];

  @override
  void log(ProductEvent event, [Map<String, Object?> props = const {}]) =>
      logged.add((event, props));
}

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('not installed: invites and opens the offer ($mode)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final events = _Events();
      final probe = ProviderContainer();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeWidgetStoreProvider.overrideWithValue(
              FakeHomeWidgetStore(installed: const []),
            ),
            productEventsProvider.overrideWithValue(events),
          ],
          child: MaterialApp(
            theme:
                dark
                    ? probe.read(themeDataDarkProvider)
                    : probe.read(themeDataLightProvider),
            home: const Scaffold(body: WidgetAddTile()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('home_widget_add_row'), findsOneWidget);
      expect(find.text('home_widget_add_row_idle'), findsOneWidget);
      await tester.tap(find.text('home_widget_add_row'));
      await tester.pumpAndSettle();
      expect(find.text('home_widget_add_title'), findsOneWidget);
      expect(events.logged.single.$2, {'source': 'settings'});
      expect(tester.takeException(), isNull);
    });

    testWidgets('installed: says so and opens straight on the steps ($mode)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final probe = ProviderContainer();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeWidgetStoreProvider.overrideWithValue(
              FakeHomeWidgetStore(installed: const ['medium']),
            ),
            productEventsProvider.overrideWithValue(_Events()),
          ],
          child: MaterialApp(
            theme:
                dark
                    ? probe.read(themeDataDarkProvider)
                    : probe.read(themeDataLightProvider),
            home: const Scaffold(body: WidgetAddTile()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('home_widget_add_row_installed'), findsOneWidget);
      await tester.tap(find.text('home_widget_add_row'));
      await tester.pumpAndSettle();
      expect(find.text('home_widget_add_steps_more_title'), findsOneWidget);
      expect(find.text('home_widget_add_confirm'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
