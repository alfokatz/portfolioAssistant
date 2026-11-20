// Temas y medios: notifier (optimista, topes, deshacer), reglas de "por
// defecto" y pantalla. Sin traducciones cargadas `.tr()` devuelve la clave.
// Correr: flutter test test/features/news_preferences
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_repository.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_claim.dart';
import 'package:portfolio_assistant/features/news_preferences/data/news_preferences_repository.dart';
import 'package:portfolio_assistant/features/news_preferences/domain/news_preferences.dart';
import 'package:portfolio_assistant/features/news_preferences/providers/news_preferences_provider.dart';
import 'package:portfolio_assistant/features/news_preferences/view/news_preferences_screen.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

import '../daily_brief/fakes/daily_brief_fakes.dart';
import '../subscription/paywall_test_harness.dart';
import 'fakes/news_preferences_fakes.dart';

NewsPreferencesNotifier _notifier(
  FakeNewsPreferencesStore store, {
  Set<String> held = const {'GGAL.BA', 'NVDA'},
  List<(ProductEvent, Map<String, Object?>)>? events,
}) => NewsPreferencesNotifier(
  store: store,
  heldTickers: () => held,
  logEvent: (e, p) => events?.add((e, p)),
);

void main() {
  group('marketOfTicker', () {
    test('suffix rule, no ticker lists', () {
      expect(marketOfTicker('NVDA'), 'US');
      expect(marketOfTicker('GGAL.BA'), '.BA');
      expect(marketOfTicker('san.mc'), '.MC');
      expect(marketOfTicker('BRK.'), 'US');
    });
  });

  group('NewsPreferencesNotifier', () {
    test(
      'defaults come from the portfolio markets; user changes win',
      () async {
        final n = _notifier(
          FakeNewsPreferencesStore(userTopicsInit: {'fed_rates': false}),
        );
        await n.load();
        final s = n.state;
        final byId = {for (final t in s.topics) t.id: t};
        expect(s.isDefault(byId['ar_bcra_dollar']!), isTrue);
        expect(s.isFollowed(byId['ar_bcra_dollar']!), isTrue);
        expect(s.isFollowed(byId['fed_rates']!), isFalse);
        expect(s.isFollowed(byId['crypto']!), isFalse);
        // Sin .BA en la cartera, ese tema no es por defecto.
        final n2 = _notifier(FakeNewsPreferencesStore(), held: {'NVDA'});
        await n2.load();
        expect(n2.state.isDefault(byId['ar_bcra_dollar']!), isFalse);
      },
    );

    test('official sources are not offered', () async {
      final n = _notifier(FakeNewsPreferencesStore());
      await n.load();
      expect(n.state.sources.map((s) => s.domain), [
        'reuters.com',
        'infobae.com',
      ]);
    });

    test('follow persists and logs without tickers', () async {
      final store = FakeNewsPreferencesStore();
      final events = <(ProductEvent, Map<String, Object?>)>[];
      final n = _notifier(store, events: events);
      await n.load();
      final crypto = n.state.topics.firstWhere((t) => t.id == 'crypto');
      expect(await n.setTopic(crypto, followed: true), isNull);
      expect(store.writes, ['topic:crypto:true']);
      expect(n.state.isFollowed(crypto), isTrue);
      expect(events.single.$1, ProductEvent.newsTopicChanged);
      expect(events.single.$2, {
        'topic_id': 'crypto',
        'followed': true,
        'was_default': false,
      });
    });

    test('unfollowing a default stores followed=false', () async {
      final store = FakeNewsPreferencesStore();
      final n = _notifier(store);
      await n.load();
      final fed = n.state.topics.first;
      await n.setTopic(fed, followed: false);
      expect(store.userTopicsData['fed_rates'], isFalse);
      expect(n.state.isFollowed(fed), isFalse);
    });

    test('server failure rolls back and returns the typed failure', () async {
      final store = FakeNewsPreferencesStore(
        failWith: const TopicLimitReached(),
      );
      final n = _notifier(store);
      await n.load();
      final crypto = n.state.topics.firstWhere((t) => t.id == 'crypto');
      expect(
        await n.setTopic(crypto, followed: true),
        isA<TopicLimitReached>(),
      );
      expect(n.state.isFollowed(crypto), isFalse);
    });

    test('topic limit is checked before calling the server', () async {
      final store = FakeNewsPreferencesStore(
        userTopicsInit: {
          for (var i = 0; i < NewsPreferencesLimits.topics; i++) 't$i': true,
        },
      );
      final n = _notifier(store);
      await n.load();
      final crypto = n.state.topics.firstWhere((t) => t.id == 'crypto');
      expect(
        await n.setTopic(crypto, followed: true),
        isA<TopicLimitReached>(),
      );
      expect(store.writes, isEmpty);
    });

    test('source prefer, mute and clear; limit per list', () async {
      final store = FakeNewsPreferencesStore(
        userSourcesInit: {
          for (var i = 0; i < NewsPreferencesLimits.sourcesPerList; i++)
            'm$i.com': SourcePreference.mute,
        },
      );
      final events = <(ProductEvent, Map<String, Object?>)>[];
      final n = _notifier(store, events: events);
      await n.load();
      final reuters = n.state.sources.first;
      expect(await n.setSource(reuters, SourcePreference.prefer), isNull);
      expect(n.state.preferenceOf('reuters.com'), SourcePreference.prefer);
      expect(await n.setSource(reuters, null), isNull);
      expect(n.state.preferenceOf('reuters.com'), isNull);
      expect(events.last.$2, {'domain': 'reuters.com', 'preference': 'none'});
      // La lista de silenciados está llena.
      expect(
        await n.setSource(reuters, SourcePreference.mute),
        isA<SourceLimitReached>(),
      );
    });

    test('load failure is a flag', () async {
      final n = _notifier(FakeNewsPreferencesStore(loadFails: true));
      await n.load();
      expect(n.state.loadFailed, isTrue);
      expect(n.state.loaded, isFalse);
    });
  });

  group('NewsPreferencesScreen', () {
    Future<FakeNewsPreferencesStore> pump(
      WidgetTester tester, {
      Brightness brightness = Brightness.light,
      DailyBriefStatus status = const DailyBriefStatus(enabled: true),
    }) async {
      tester.view.physicalSize = const Size(375, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = FakeNewsPreferencesStore();
      final h = PaywallHarness();
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...h.overrides,
            newsPreferencesStoreProvider.overrideWithValue(store),
            dailyBriefRepositoryProvider.overrideWithValue(
              FakeDailyBriefStore(statusResult: status),
            ),
          ],
          child: MaterialApp(
            theme: c.read(
              brightness == Brightness.dark
                  ? themeDataDarkProvider
                  : themeDataLightProvider,
            ),
            home: const NewsPreferencesScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      return store;
    }

    for (final brightness in Brightness.values) {
      testWidgets('lists topics and outlets in ${brightness.name}', (
        tester,
      ) async {
        await pump(tester, brightness: brightness);
        expect(tester.takeException(), isNull);
        expect(find.text('news_prefs_topics_title'), findsOneWidget);
        expect(find.text('Fed y tasas'), findsOneWidget);
        expect(find.text('news_prefs_default_badge'), findsWidgets);
        expect(find.text('Reuters'), findsOneWidget);
        expect(find.text('Fed'), findsNothing);
      });
    }

    testWidgets('switch follows a topic', (tester) async {
      final store = await pump(tester);
      final row = find.ancestor(
        of: find.text('Cripto'),
        matching: find.byType(MergeSemantics),
      );
      await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
      await tester.pump();
      expect(store.writes, ['topic:crypto:true']);
    });

    testWidgets('sources piece off hides the outlets', (tester) async {
      await pump(
        tester,
        status: const DailyBriefStatus(
          enabled: true,
          pieces: {'sources': false},
        ),
      );
      expect(find.text('news_prefs_sources_title'), findsNothing);
      expect(find.text('news_prefs_topics_title'), findsOneWidget);
    });
  });
}
