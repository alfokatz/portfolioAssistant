// WidgetPromptWatcher: ofrece la hoja solo a partir de la 3.ª apertura, con
// cartera, sin widget instalado, con la Home a la vista y sin nada encima, y
// una sola vez por apertura. Correr: flutter test test/features/home_widget/view/widget_prompt_watcher_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/home_widget/data/home_widget_store.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_prompt_provider.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_settings_provider.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_prompt_watcher.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/providers/portfolio_diagnosis_provider.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../home_widget_test_helpers.dart';

class _Home extends StateNotifier<HomeState> implements HomeProvider {
  _Home(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Seen extends DiagnosisSeenNotifier {
  _Seen() : super(null, null) {
    state = true;
  }
}

class _Events extends ProductEvents {
  _Events() : super(client: () => null, prefs: () => null);
  final logged = <(ProductEvent, Map<String, Object?>)>[];

  @override
  void log(ProductEvent event, [Map<String, Object?> props = const {}]) =>
      logged.add((event, props));

  int count(ProductEvent e) => logged.where((l) => l.$1 == e).length;
}

HomeState _home(int positions) => HomeState(
  summary: PortfolioSummary(
    totalValue: 100.0 * positions,
    totalCostBasis: 100.0 * positions,
    totalPnlAbsolute: 0,
    totalPnlPercent: 0,
    valuations: [
      for (var i = 0; i < positions; i++)
        PortfolioCalculator.valuate(
          position: Position(
            id: '$i',
            ticker: 'T$i',
            quantity: 1,
            purchasePrice: 100,
            purchaseDate: DateTime(2025),
          ),
          currentPrice: 100,
        ),
    ],
  ),
);

void main() {
  late _Home home;
  late _Events events;
  late FakeHomeWidgetStore store;
  late SharedPreferences prefs;
  late ProviderContainer container;
  const delay = Duration(milliseconds: 50);

  Future<void> pump(
    WidgetTester tester, {
    int opens = 3,
    int positions = 2,
    List<String> installed = const [],
    bool isHome = true,
    Map<String, Object> extraPrefs = const {},
  }) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      WidgetPrefsKeys.promptOpens: opens,
      ...extraPrefs,
    });
    prefs = await SharedPreferences.getInstance();
    home = _Home(_home(positions));
    events = _Events();
    store = FakeHomeWidgetStore(installed: installed);
    final probe = ProviderContainer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          homeProvider.overrideWith((ref) => home),
          diagnosisSeenProvider.overrideWith((ref) => _Seen()),
          homeWidgetStoreProvider.overrideWithValue(store),
          productEventsProvider.overrideWithValue(events),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              theme: probe.read(themeDataLightProvider),
              home: WidgetPromptWatcher(
                isHome: isHome,
                settleDelay: delay,
                child: const Scaffold(body: Text('home')),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> wait(WidgetTester tester) async {
    await tester.pump(delay * 2);
    await tester.pumpAndSettle();
  }

  testWidgets('3rd open with portfolio: offers once and stores the count', (
    tester,
  ) async {
    await pump(tester);
    await wait(tester);
    expect(find.text('home_widget_add_title'), findsOneWidget);
    expect(prefs.getInt(WidgetPrefsKeys.promptShown), 1);
    expect(events.count(ProductEvent.widgetPromptShown), 1);

    await tester.tap(find.text('home_widget_add_later'));
    await tester.pumpAndSettle();
    // Cambios en la Home y más tiempo en la misma apertura: no vuelve.
    home.state = _home(3);
    await wait(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('home_widget_add_title'), findsNothing);
    expect(events.count(ProductEvent.widgetPromptShown), 1);
    expect(events.count(ProductEvent.widgetPromptDismissed), 1);

    // Otra apertura: sigue el cooldown de 30 días.
    await container.read(widgetPromptProvider.notifier).registerOpen();
    await wait(tester);
    expect(find.text('home_widget_add_title'), findsNothing);
  });

  testWidgets('2nd open: not yet; the 3rd one offers it', (tester) async {
    await pump(tester, opens: 2);
    await wait(tester);
    expect(find.text('home_widget_add_title'), findsNothing);
    await container.read(widgetPromptProvider.notifier).registerOpen();
    await wait(tester);
    expect(find.text('home_widget_add_title'), findsOneWidget);
  });

  testWidgets('a widget already installed: never', (tester) async {
    await pump(tester, installed: const ['small']);
    await wait(tester);
    expect(find.text('home_widget_add_title'), findsNothing);
    expect(events.logged, isEmpty);
    expect(prefs.getInt(WidgetPrefsKeys.promptShown), isNull);
  });

  testWidgets('no portfolio: never; once loaded, it offers', (tester) async {
    await pump(tester, positions: 0);
    await wait(tester);
    expect(find.text('home_widget_add_title'), findsNothing);
    home.state = _home(1);
    await wait(tester);
    expect(find.text('home_widget_add_title'), findsOneWidget);
  });

  testWidgets('not on the Home tab: waits', (tester) async {
    await pump(tester, isHome: false);
    await wait(tester);
    expect(find.text('home_widget_add_title'), findsNothing);
  });

  testWidgets('30 days not over / 2 offers already made: no', (tester) async {
    final recent =
        DateTime.now()
            .subtract(const Duration(days: 10))
            .millisecondsSinceEpoch;
    await pump(
      tester,
      extraPrefs: {
        WidgetPrefsKeys.promptShown: 1,
        WidgetPrefsKeys.promptLastAt: recent,
      },
    );
    await wait(tester);
    expect(find.text('home_widget_add_title'), findsNothing);
  });

  testWidgets('30 days over: offers a second time, never a third', (
    tester,
  ) async {
    final old =
        DateTime.now()
            .subtract(const Duration(days: 31))
            .millisecondsSinceEpoch;
    await pump(
      tester,
      extraPrefs: {
        WidgetPrefsKeys.promptShown: 1,
        WidgetPrefsKeys.promptLastAt: old,
      },
    );
    await wait(tester);
    expect(find.text('home_widget_add_title'), findsOneWidget);
    expect(prefs.getInt(WidgetPrefsKeys.promptShown), 2);

    await tester.tap(find.text('home_widget_add_later'));
    await tester.pumpAndSettle();
    await container.read(widgetPromptProvider.notifier).registerOpen();
    // Aunque pasen los días, ya van 2.
    expect(
      container
          .read(widgetPromptProvider.notifier)
          .shouldOffer(installed: false, hasPortfolio: true),
      isFalse,
    );
  });

  testWidgets('another sheet on top: does not stack on it', (tester) async {
    await pump(tester);
    final context = tester.element(find.text('home'));
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SizedBox(height: 200, child: Text('other')),
    );
    await tester.pumpAndSettle();
    await wait(tester);
    expect(find.text('other'), findsOneWidget);
    expect(find.text('home_widget_add_title'), findsNothing);
    expect(events.count(ProductEvent.widgetPromptShown), 0);
  });
}
