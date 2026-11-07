// Toques de novedades del widget: ítem por id (caché del usuario, vigente),
// avisos en Android (paywall con source y motivo) y en iOS (hoja bloqueada
// que abre el paywall adentro), nada antes del login y eventos sin ticker.
// Correr: flutter test test/features/home_widget/view
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_router.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/home_widget/data/home_widget_store.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_items_cache.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_settings_provider.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_launch_listener.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_news_sheet.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../subscription/paywall_test_harness.dart';
import '../home_widget_test_helpers.dart';

const _newsId = 'a1b2c3d4';
const _earningsId = 'e5f6a7b8';

Uri _uri(String query) =>
    Uri.parse('porty-widget://open?homeWidget&$query');

void main() {
  late FakeHomeWidgetStore store;
  late PaywallHarness h;
  late SharedPreferences prefs;
  late List<Object?> assistantExtras;
  late List<Uri> opened;

  Future<void> seed({String uid = 'u1', Duration newsAge = const Duration(hours: 3)}) async {
    final now = DateTime.now();
    await WidgetItemsCache(prefs).write(
      WidgetItemsCacheEntry(
        uid: uid,
        checkedAt: now,
        tier: 'gold',
        top: 'AAA',
        teasersEnabled: false,
        itemsSection: true,
        items: [
          WidgetCachedItem(
            id: _earningsId,
            kind: 'earnings',
            ticker: 'ZZZ',
            date: DateTime(now.year, now.month, now.day + 1),
            expiresAt: now.add(const Duration(days: 2)),
          ),
          WidgetCachedItem(
            id: _newsId,
            kind: 'news',
            ticker: 'AAA',
            headline: 'AAA abre una planta',
            source: 'Fuente Ejemplo',
            url: 'https://example.com/a',
            publishedAt: now.subtract(newsAge),
            expiresAt: now.subtract(newsAge).add(const Duration(hours: 48)),
          ),
        ],
      ),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    String? initial,
    bool withSession = true,
    SubscriptionTier tier = SubscriptionTier.gold,
    String platform = 'ios',
    String? uid = 'u1',
  }) async {
    tester.view.physicalSize = const Size(375, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    resetWidgetLaunchInitialHandled();
    store =
        FakeHomeWidgetStore()
          ..platformName = platform
          ..initial = initial == null ? null : Uri.parse(initial);
    h = PaywallHarness(tier: tier);
    assistantExtras = [];
    opened = [];
    final themes = ProviderContainer();
    addTearDown(themes.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (_, __) => const Scaffold(
                body: WidgetLaunchListener(child: Text('home')),
              ),
        ),
        GoRoute(
          name: AssistantRouter.routeName,
          path: AssistantRouter.path,
          builder: (_, state) {
            assistantExtras.add(state.extra);
            return const Text('assistant');
          },
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...h.overrides,
          sharedPreferencesProvider.overrideWithValue(prefs),
          homeWidgetStoreProvider.overrideWithValue(store),
          widgetLaunchedWithSessionProvider.overrideWithValue(withSession),
          widgetCurrentUserIdProvider.overrideWithValue(() => uid),
          widgetUrlLauncherProvider.overrideWithValue((u) async {
            opened.add(u);
            return true;
          }),
        ],
        child: MaterialApp.router(
          theme: themes.read(themeDataLightProvider),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('news item opens the sheet with it on top and logs widget_opened',
      (tester) async {
    await seed();
    await pump(
      tester,
      initial: _uri('target=news&id=$_newsId&rank=2&size=large&age=5').toString(),
    );
    await tester.pumpAndSettle();

    expect(find.text('home_widget_sheet_title'), findsOneWidget);
    expect(find.text('AAA abre una planta'), findsOneWidget);
    // El tocado va arriba del de resultados.
    final newsY = tester.getTopLeft(find.text('AAA abre una planta')).dy;
    final earnY = tester.getTopLeft(find.textContaining('home_widget_earnings')).dy;
    expect(newsY, lessThan(earnY));

    final props = h.events.of(ProductEvent.widgetOpened).single;
    expect(props['target'], 'news');
    expect(props['size'], 'large');
    expect(props['item_rank'], 2);
    expect(props['item_age_h'], 3);
    expect(props['tier'], isNotNull);
    expect(props.toString(), isNot(contains('AAA')));
    expect(props.toString(), isNot(contains(_newsId)));
  });

  testWidgets('unknown or expired id: nothing opens, no query spent',
      (tester) async {
    await seed(newsAge: const Duration(hours: 49));
    await pump(tester, initial: _uri('target=news&id=$_newsId&rank=1').toString());
    await tester.pumpAndSettle();
    expect(find.text('home_widget_sheet_title'), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(assistantExtras, isEmpty);

    store.controller.add(_uri('target=news&id=deadbeef&rank=1'));
    store.controller.add(_uri('target=news&id=NOT-HEX&rank=1'));
    await tester.pumpAndSettle();
    expect(find.text('home_widget_sheet_title'), findsNothing);
  });

  testWidgets('cache of another user is not shown', (tester) async {
    await seed(uid: 'otro');
    await pump(tester, initial: _uri('target=news&id=$_newsId').toString());
    await tester.pumpAndSettle();
    expect(find.text('home_widget_sheet_title'), findsNothing);
  });

  testWidgets('nothing happens for novelty taps from before the login',
      (tester) async {
    await seed();
    await pump(
      tester,
      initial: _uri('target=news&id=$_newsId').toString(),
      withSession: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('home_widget_sheet_title'), findsNothing);
    expect(h.events.logged.where((e) => e.$1 == ProductEvent.widgetOpened), isEmpty);

    await pump(
      tester,
      initial: _uri('target=teaser_news&size=large').toString(),
      withSession: false,
      tier: SubscriptionTier.free,
      platform: 'android',
    );
    await tester.pumpAndSettle();
    expect(h.events.of(ProductEvent.paywallViewed), isEmpty);
  });

  testWidgets('android free teaser opens the held-news paywall with its source',
      (tester) async {
    await seed();
    await pump(
      tester,
      initial: _uri('target=teaser_news&size=large').toString(),
      tier: SubscriptionTier.free,
      platform: 'android',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    final viewed = h.events.of(ProductEvent.paywallViewed).single;
    expect(viewed['source'], 'widget_held_news');
    expect(viewed['reason'], 'heldNews');
    expect(h.events.of(ProductEvent.widgetOpened).single['target'], 'teaser_news');
  });

  testWidgets('android premium earnings teaser opens the gold paywall',
      (tester) async {
    await seed();
    await pump(
      tester,
      initial: _uri('target=teaser_earnings&size=medium').toString(),
      tier: SubscriptionTier.premium,
      platform: 'android',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    final viewed = h.events.of(ProductEvent.paywallViewed).single;
    expect(viewed['source'], 'widget_earnings');
    expect(viewed['reason'], 'goldRequired');
  });

  testWidgets('ios teaser opens the locked sheet; the paywall is inside the app',
      (tester) async {
    await seed();
    await pump(
      tester,
      initial: _uri('target=teaser_news&size=large').toString(),
      tier: SubscriptionTier.free,
      platform: 'ios',
    );
    await tester.pumpAndSettle();

    // Hoja bloqueada, sin paywall directo desde el toque.
    expect(find.text('home_widget_locked_premium'), findsOneWidget);
    expect(h.events.of(ProductEvent.paywallViewed), isEmpty);

    await tester.tap(find.text('assistant_quota_nudge_cta'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(h.events.of(ProductEvent.paywallViewed).single['source'], 'widget_held_news');
    final action = h.events.of(ProductEvent.widgetItemAction).single;
    expect(action, {'action': 'open_paywall', 'type': 'news', 'from_widget': true});
  });

  testWidgets('teaser when the plan already includes it opens the items',
      (tester) async {
    await seed();
    await pump(
      tester,
      initial: _uri('target=teaser_news&size=large').toString(),
      tier: SubscriptionTier.gold,
      platform: 'android',
    );
    await tester.pumpAndSettle();
    expect(find.text('AAA abre una planta'), findsOneWidget);
    expect(h.events.of(ProductEvent.paywallViewed), isEmpty);
  });

  testWidgets('sheet: read on source, ask Porty and item events', (tester) async {
    await seed();
    await pump(tester, initial: _uri('target=news&id=$_newsId&rank=1').toString());
    await tester.pumpAndSettle();

    await tester.tap(find.text('home_widget_read_on'));
    await tester.pump();
    expect(opened.single.toString(), 'https://example.com/a');

    await tester.tap(find.text('home_widget_ask_porty'));
    await tester.pumpAndSettle();
    final request = assistantExtras.single as AssistantQuestionRequest;
    expect(request.question, 'home_widget_question_news_why');
    expect((request.origin! as WidgetQuestionOrigin).questionId, 'news_why');

    final actions = h.events.of(ProductEvent.widgetItemAction);
    expect(actions, [
      {'action': 'read_source', 'type': 'news', 'from_widget': true},
      {'action': 'ask_porty', 'type': 'news', 'from_widget': true},
    ]);
    expect(actions.toString(), isNot(contains('AAA')));
  });

  testWidgets('earnings item asks the earnings_when question', (tester) async {
    await seed();
    await pump(tester, initial: _uri('target=earnings&id=$_earningsId&rank=1').toString());
    await tester.pumpAndSettle();
    expect(find.text('home_widget_read_on'), findsNothing);
    await tester.tap(find.text('home_widget_ask_porty'));
    await tester.pumpAndSettle();
    final request = assistantExtras.single as AssistantQuestionRequest;
    expect(request.question, 'home_widget_question_earnings_when');
    expect((request.origin! as WidgetQuestionOrigin).questionId, 'earnings_when');
  });

  testWidgets('sheet shows the legend without overflow at 375 wide',
      (tester) async {
    await seed();
    await pump(tester, initial: _uri('target=news&id=$_newsId').toString());
    await tester.pumpAndSettle();
    expect(find.text('home_widget_sheet_legend'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
