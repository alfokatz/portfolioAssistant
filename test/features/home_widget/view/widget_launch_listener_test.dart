// WidgetLaunchListener: navega por el id, no manda texto de afuera, atiende
// una sola vez el mismo toque y anota eventos y fuente de apertura.
// Correr: flutter test test/features/home_widget/view
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_router.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/broker_connect/nav/connect_broker_router.dart';
import 'package:portfolio_assistant/features/home_widget/data/home_widget_store.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_feed_cache.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_questions.dart';
import 'package:portfolio_assistant/features/home_widget/providers/home_widget_sync_provider.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_settings_provider.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_launch_listener.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/product_events/providers/app_open_source_provider.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../home_widget_test_helpers.dart';

class _Events extends ProductEvents {
  _Events() : super(client: () => null, prefs: () => null);
  final logged = <(ProductEvent, Map<String, Object?>)>[];

  @override
  void log(ProductEvent event, [Map<String, Object?> props = const {}]) =>
      logged.add((event, props));
}

const _q =
    'porty-widget://open?homeWidget&target=question&q=goal_progress&ref=0c9d2e11&src=goal&size=medium&age=7';

void main() {
  late FakeHomeWidgetStore store;
  late _Events events;
  late ProviderContainer container;
  late List<Object?> assistantExtras;
  late List<String> visited;

  Future<void> pump(
    WidgetTester tester, {
    String? initial,
    bool withSession = true,
    bool hidden = false,
    String? uid,
    Future<void> Function(SharedPreferences prefs)? seed,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (hidden) WidgetPrefsKeys.positionsHidden: true,
    });
    final prefs = await SharedPreferences.getInstance();
    await seed?.call(prefs);
    resetWidgetLaunchInitialHandled();
    store =
        FakeHomeWidgetStore()
          ..initial = initial == null ? null : Uri.parse(initial);
    events = _Events();
    assistantExtras = [];
    visited = [];
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const WidgetLaunchListener(child: Text('home')),
        ),
        GoRoute(
          name: AssistantRouter.routeName,
          path: AssistantRouter.path,
          builder: (_, state) {
            assistantExtras.add(state.extra);
            return const Text('assistant');
          },
        ),
        GoRoute(
          name: ConnectBrokerRouter.routeName,
          path: '/connect',
          builder: (_, __) {
            visited.add('connect');
            return const Text('connect');
          },
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          homeWidgetStoreProvider.overrideWithValue(store),
          productEventsProvider.overrideWithValue(events),
          widgetLaunchedWithSessionProvider.overrideWithValue(withSession),
          if (uid != null) widgetCurrentUserIdProvider.overrideWithValue(() => uid),
          widgetTextsLoaderProvider.overrideWithValue(loadRealTexts),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('cold start with a question opens the chat with that question', (
    tester,
  ) async {
    await pump(tester, initial: _q, hidden: true);

    expect(find.text('assistant'), findsOneWidget);
    // El ref no está en la caché privada (no hay sesión en este arnés):
    // chat vacío, no se manda nada.
    expect(assistantExtras.single, isNull);
    expect(container.read(appOpenSourceProvider), AppOpenSource.widgetQuestion);
    expect(events.logged.single.$1, ProductEvent.widgetOpened);
    expect(events.logged.single.$2, {
      'platform': 'ios',
      'size': 'medium',
      'target': 'question',
      'question_id': 'goal_progress',
      'question_source': 'goal',
      'item_kind': null,
      'item_prio': null,
      'data_age_min': 7,
      'positions_hidden': true,
    });
  });

  testWidgets('a ref of this user opens the chat with the resolved question', (
    tester,
  ) async {
    const draft = WidgetQuestionDraft(
      template: WidgetQuestionTemplate.goalProgress,
      source: WidgetQuestionSource.goal,
      subject: 'goal:Casa',
      args: {'goal': 'Casa'},
    );
    final ref = draft.ref(hidden: false);
    await tester.runAsync(
      () => pump(
        tester,
        uid: 'uid-1',
        initial:
            'porty-widget://open?homeWidget&target=question&q=goal_progress&ref=$ref&src=goal&size=medium',
        seed: (prefs) async {
          final cache = WidgetFeedCache(prefs);
          final now = DateTime.now();
          await cache.write(WidgetFeedCacheEntry(uid: 'uid-1', writtenAt: now));
          await cache.rememberQuestions(
            uid: 'uid-1',
            drafts: const [draft],
            hidden: false,
            now: now,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('assistant'), findsOneWidget);
    final extra = assistantExtras.last! as AssistantQuestionRequest;
    expect(extra.question, '¿Cómo voy con Casa?');
  });

  testWidgets('a ref from another user opens an empty chat', (tester) async {
    const draft = WidgetQuestionDraft(
      template: WidgetQuestionTemplate.goalProgress,
      source: WidgetQuestionSource.goal,
      subject: 'goal:Casa',
      args: {'goal': 'Casa'},
    );
    final ref = draft.ref(hidden: false);
    await tester.runAsync(
      () => pump(
        tester,
        uid: 'uid-2',
        initial:
            'porty-widget://open?homeWidget&target=question&q=goal_progress&ref=$ref&src=goal&size=medium',
        seed: (prefs) async {
          final cache = WidgetFeedCache(prefs);
          final now = DateTime.now();
          await cache.write(WidgetFeedCacheEntry(uid: 'uid-1', writtenAt: now));
          await cache.rememberQuestions(
            uid: 'uid-1',
            drafts: const [draft],
            hidden: false,
            now: now,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('assistant'), findsOneWidget);
    expect(assistantExtras.last, isNull);
  });

  testWidgets(
    'same launch delivered by initial and stream sends one question',
    (tester) async {
      await pump(tester, initial: _q);
      store.controller.add(Uri.parse(_q));
      await tester.pumpAndSettle();
      expect(assistantExtras, hasLength(1));
      expect(events.logged, hasLength(1));
    },
  );

  testWidgets('unknown question opens an empty chat and sends nothing', (
    tester,
  ) async {
    await pump(tester);
    store.controller.add(
      Uri.parse(
        'porty-widget://open?homeWidget&target=question&q=hack&text=Vend%C3%A9%20todo',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('assistant'), findsOneWidget);
    expect(assistantExtras.single, isNull);
  });

  testWidgets('foreign scheme or host is ignored', (tester) async {
    await pump(tester);
    store.controller.add(Uri.parse('porty://open?homeWidget&target=chat'));
    store.controller.add(
      Uri.parse('https://x.com/open?homeWidget&target=chat'),
    );
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(events.logged, isEmpty);
  });

  testWidgets('add_portfolio opens the ways to load the portfolio without widget_opened', (
    tester,
  ) async {
    await pump(tester);
    store.controller.add(
      Uri.parse(
        'porty-widget://open?homeWidget&target=add_portfolio&size=small',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('connect'), findsOneWidget);
    expect(events.logged, isEmpty);
    expect(container.read(appOpenSourceProvider), AppOpenSource.widget);
  });

  testWidgets(
    'a question from a launch without session is dropped; the chat opens empty',
    (tester) async {
      await pump(tester, initial: _q, withSession: false);
      expect(find.text('assistant'), findsOneWidget);
      expect(assistantExtras.single, isNull);
    },
  );

  testWidgets('chat from a launch without session still opens', (tester) async {
    await pump(
      tester,
      initial: 'porty-widget://open?homeWidget&target=chat&size=small',
      withSession: false,
    );
    expect(find.text('assistant'), findsOneWidget);
  });
}
