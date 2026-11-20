// WidgetPositionsTile: el switch guarda el ajuste, loguea el evento y muestra
// el texto de privacidad; claro y oscuro, ancho 375.
// Correr: flutter test test/features/home_widget/view/widget_positions_tile_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_settings_provider.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_positions_tile.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Events extends ProductEvents {
  _Events() : super(client: () => null, prefs: () => null);
  final logged = <(ProductEvent, Map<String, Object?>)>[];

  @override
  void log(ProductEvent event, [Map<String, Object?> props = const {}]) =>
      logged.add((event, props));
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'toggle saves the setting and logs the event (${dark ? 'dark' : 'light'})',
      (tester) async {
        tester.view.physicalSize = const Size(375, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final events = _Events();
        final probe = ProviderContainer();
        final theme =
            dark
                ? probe.read(themeDataDarkProvider)
                : probe.read(themeDataLightProvider);
        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              productEventsProvider.overrideWithValue(events),
            ],
            child: Builder(
              builder: (context) {
                container = ProviderScope.containerOf(context);
                return MaterialApp(
                  theme: theme,
                  home: const Scaffold(body: WidgetPositionsTile()),
                );
              },
            ),
          ),
        );

        // Sin traducciones cargadas, .tr() devuelve la clave.
        expect(find.text('home_widget_hide_positions'), findsOneWidget);
        expect(find.text('home_widget_positions_privacy_note'), findsOneWidget);
        expect(container.read(widgetPositionsHiddenProvider), isFalse);

        await tester.tap(find.byType(Switch));
        await tester.pump();

        expect(container.read(widgetPositionsHiddenProvider), isTrue);
        expect(prefs.getBool(WidgetPrefsKeys.positionsHidden), isTrue);
        expect(events.logged.single.$1, ProductEvent.widgetPositionsToggled);
        expect(events.logged.single.$2, {'hidden': true});
        expect(tester.takeException(), isNull);
      },
    );
  }
}
