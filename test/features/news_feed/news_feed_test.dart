// Feed de noticias, Mercado hoy, tema y videos: parseo de los fixtures del
// contrato, gating por plan, orden fijo, reproductor con fallback. Sin
// traducciones cargadas `.tr()` devuelve la clave. Correr:
// flutter test test/features/news_feed
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_repository.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_claim.dart';
import 'package:portfolio_assistant/features/daily_brief/providers/daily_brief_provider.dart';
import 'package:portfolio_assistant/features/news_feed/domain/news_bundle.dart';
import 'package:portfolio_assistant/features/news_feed/providers/news_feed_provider.dart';
import 'package:portfolio_assistant/features/news_feed/view/market_today_screen.dart';
import 'package:portfolio_assistant/features/news_feed/view/news_feed_screen.dart';
import 'package:portfolio_assistant/features/news_feed/view/news_topic_screen.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/news_video_sheet.dart';
import 'package:portfolio_assistant/features/news_preferences/data/news_preferences_repository.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/subscription/config/paywall_source.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

import '../daily_brief/fakes/daily_brief_fakes.dart';
import '../news_preferences/fakes/news_preferences_fakes.dart';
import '../subscription/paywall_test_harness.dart';

/// Responde un fixture distinto por scope.
class _ScopedStore extends FakeDailyBriefStore {
  _ScopedStore(
    this.bodies, {
    DailyBriefStatus status = const DailyBriefStatus(enabled: true),
  }) : super(statusResult: status);

  final Map<String, Map<String, Object?>> bodies;
  final topics = <String?>[];

  @override
  Future<Map<String, Object?>> bundle(
    String scope, {
    required String day,
    required String lang,
    String? topic,
  }) async {
    bundleCalls.add(scope);
    topics.add(topic);
    final error = bundleError;
    if (error != null) throw error;
    return bodies[scope]!;
  }
}

ThemeData _theme(Brightness b) {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c.read(
    b == Brightness.dark ? themeDataDarkProvider : themeDataLightProvider,
  );
}

Future<PaywallHarness> _pump(
  WidgetTester tester,
  FakeDailyBriefStore store,
  Widget screen, {
  Brightness brightness = Brightness.light,
  SubscriptionTier tier = SubscriptionTier.premium,
  List<Uri>? launched,
}) async {
  tester.view.physicalSize = const Size(375, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = PaywallHarness(tier: tier);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...h.overrides,
        dailyBriefRepositoryProvider.overrideWithValue(store),
        newsPreferencesStoreProvider.overrideWithValue(
          FakeNewsPreferencesStore(),
        ),
        dailyBriefUrlLauncherProvider.overrideWithValue((uri) async {
          launched?.add(uri);
          return true;
        }),
        newsVideoPlayerBuilderProvider.overrideWithValue(
          (context, id, onError) => TextButton(
            key: const Key('fake-player'),
            onPressed: onError,
            child: Text('player:$id'),
          ),
        ),
      ],
      child: MaterialApp(theme: _theme(brightness), home: screen),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return h;
}

void main() {
  group('NewsBundle.parse', () {
    test('premium feed: held headlines, digests and videos', () {
      final b = NewsBundle.parse(bundleFixture('bundle_feed_premium'));
      expect(b.isLocked, isFalse);
      expect(b.mine.map((a) => a.ticker), ['NVDA', 'AAPL']);
      expect(b.mine.first.preferred, isTrue);
      expect(b.topics.first.status, NewsDigestStatus.ok);
      expect(b.topics.last.status, NewsDigestStatus.empty);
      expect(b.videos.single.embeddable, isTrue);
      expect(
        b.sourceOf(b.topics.first.lines.first.sourceIds)?.source,
        'Reuters',
      );
    });

    test('free feed: only a count, no tickers', () {
      final b = NewsBundle.parse(bundleFixture('bundle_feed_free'));
      expect(b.isLocked, isTrue);
      expect(b.lockedCount, 2);
      expect(b.mine, isEmpty);
    });

    test('market keeps catalog order and null pct', () {
      final b = NewsBundle.parse(bundleFixture('bundle_market'));
      expect(b.instruments.first.symbol, '^GSPC');
      expect(b.instruments.map((i) => i.symbol).toList().indexOf('^TNX'), 4);
      expect(b.instruments[4].pct, isNull);
      expect(b.pulse, hasLength(2));
    });

    test('topic scope parses topic_news without ticker', () {
      final b = NewsBundle.parse(bundleFixture('bundle_topic'));
      expect(b.topicNews, hasLength(2));
      expect(b.topicNews.first.ticker, isNull);
    });

    test('broken blocks arrive empty and a bad video id is not embeddable', () {
      final b = NewsBundle.parse({
        'mine': 'x',
        'videos': [1],
        'topics': null,
      });
      expect(b.mine, isEmpty);
      expect(b.videos, isEmpty);
      const v = NewsVideo(videoId: 'a b', title: 't', channel: 'c', url: 'u');
      expect(v.embeddable, isFalse);
    });

    test('video embeddable follows the server flag when present', () {
      Map<String, Object?> raw(Object? flag) => {
        'video_id': 'abcdefghijk',
        'title': 't',
        'channel': 'c',
        'url': 'https://youtu.be/abcdefghijk',
        'embeddable': ?flag,
      };
      expect(NewsVideo.tryParse(raw(false))!.embeddable, isFalse);
      expect(NewsVideo.tryParse(raw(true))!.embeddable, isTrue);
      // Bundle viejo: sin el campo, manda el formato del id.
      expect(NewsVideo.tryParse(raw(null))!.embeddable, isTrue);
      // Campo con tipo raro: se ignora.
      expect(NewsVideo.tryParse(raw('no'))!.embeddable, isTrue);
    });
  });

  group('NewsScopeNotifier', () {
    test('disabled and failed map to phases', () async {
      Future<NewsScopeState> run(Object error) async {
        final n = NewsScopeNotifier(() async => throw error);
        await Future<void>.delayed(Duration.zero);
        return n.state;
      }

      expect((await run(const DailyBriefDisabled())).disabled, isTrue);
      expect((await run(const DailyBriefNetworkFailure())).failed, isTrue);
    });
  });

  group('NewsFeedScreen', () {
    for (final brightness in Brightness.values) {
      testWidgets('premium shows held news with outlet in ${brightness.name}', (
        tester,
      ) async {
        final store = _ScopedStore({
          'feed': bundleFixture('bundle_feed_premium'),
        });
        final h = await _pump(
          tester,
          store,
          const NewsFeedScreen(),
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
        expect(
          find.text(
            'Nvidia supera las previsiones de ingresos y sube en el after hours',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('NVDA · Reuters'), findsOneWidget);
        expect(find.text('news_feed_compare'), findsNWidgets(2));
        expect(find.text('news_feed_locked'), findsNothing);
        expect(
          h.events.logged.map((e) => e.$1),
          contains(ProductEvent.newsFeedOpened),
        );
      });
    }

    testWidgets('free sees the count, never a ticker, and the paywall opens', (
      tester,
    ) async {
      final store = _ScopedStore({'feed': bundleFixture('bundle_feed_free')});
      final h = await _pump(
        tester,
        store,
        const NewsFeedScreen(),
        tier: SubscriptionTier.free,
      );
      expect(find.text('news_feed_locked'), findsOneWidget);
      expect(find.textContaining('NVDA'), findsNothing);
      await tester.tap(find.text('news_feed_locked'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        h.events.logged.any((e) => e.$2['source'] == PaywallSource.newsFeed),
        isTrue,
      );
    });

    testWidgets('read opens the source outside the app', (tester) async {
      final launched = <Uri>[];
      final store = _ScopedStore({
        'feed': bundleFixture('bundle_feed_premium'),
      });
      await _pump(tester, store, const NewsFeedScreen(), launched: launched);
      await tester.tap(find.text('news_feed_read_on').first);
      await tester.pump();
      expect(launched.single.host, 'www.reuters.com');
    });

    testWidgets('error shows retry and loads again', (tester) async {
      final store = _ScopedStore({'feed': bundleFixture('bundle_feed_premium')})
        ..bundleError = const DailyBriefNetworkFailure();
      await _pump(tester, store, const NewsFeedScreen());
      expect(find.text('news_feed_error'), findsOneWidget);
      store.bundleError = null;
      await tester.tap(find.text('retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('news_feed_error'), findsNothing);
      expect(store.bundleCalls, ['feed', 'feed']);
    });

    testWidgets('topics tab lists digests with their outlet', (tester) async {
      final store = _ScopedStore({
        'feed': bundleFixture('bundle_feed_premium'),
      });
      await _pump(tester, store, const NewsFeedScreen(tab: 'topics'));
      expect(find.text('Fed y tasas'), findsOneWidget);
      expect(
        find.text('La Reserva Federal mantuvo las tasas sin cambios.'),
        findsOneWidget,
      );
      expect(find.text('Reuters'), findsWidgets);
      expect(find.text('news_video_section'), findsOneWidget);
    });

    testWidgets('pieces off hide the topics and market tabs', (tester) async {
      final store = _ScopedStore(
        {'feed': bundleFixture('bundle_feed_premium')},
        status: const DailyBriefStatus(
          enabled: true,
          pieces: {'topics': false, 'market': false, 'sources': false},
        ),
      );
      // El feed lee el estado por newsStatusProvider (store.status()).
      await _pump(tester, store, const NewsFeedScreen());
      expect(find.text('news_feed_tab_topics'), findsNothing);
      expect(find.text('news_feed_tab_market'), findsNothing);
    });
  });

  group('MarketTodayScreen', () {
    testWidgets('why first, then instruments in catalog order, no rankings', (
      tester,
    ) async {
      final store = _ScopedStore({'market': bundleFixture('bundle_market')});
      final h = await _pump(tester, store, const MarketTodayScreen());
      expect(find.text('market_today_why_title'), findsOneWidget);
      final why = tester.getTopLeft(find.text('market_today_why_title')).dy;
      final inst =
          tester.getTopLeft(find.text('market_today_instruments_title')).dy;
      expect(why, lessThan(inst));
      final order =
          [
            'S&P 500',
            'Nasdaq',
            'Dow Jones',
            'Petróleo WTI',
            'Bono a 10 años de EE. UU.',
            'Bitcoin',
          ].map((l) => tester.getTopLeft(find.text(l)).dy).toList();
      expect(order, [...order]..sort());
      expect(find.text('—'), findsOneWidget);
      expect(
        h.events.logged.map((e) => e.$1),
        contains(ProductEvent.marketTodayOpened),
      );
    });

    testWidgets('empty market says so', (tester) async {
      final store = _ScopedStore({
        'market': {
          'market': {'instruments': [], 'pulse': []},
          'videos': [],
        },
      });
      await _pump(tester, store, const MarketTodayScreen());
      expect(find.text('market_today_empty'), findsOneWidget);
    });
  });

  group('NewsTopicScreen', () {
    testWidgets('shows digest, headlines and asks the right topic', (
      tester,
    ) async {
      final store = _ScopedStore({'topic': bundleFixture('bundle_topic')});
      await _pump(tester, store, const NewsTopicScreen(topicId: 'fed_rates'));
      expect(store.topics, ['fed_rates']);
      expect(find.text('news_topic_screen_headlines'), findsOneWidget);
      expect(
        find.text('Fed holds rates steady and signals patience'),
        findsOneWidget,
      );
    });

    testWidgets('free compare on a topic opens the paywall', (tester) async {
      final store = _ScopedStore({'topic': bundleFixture('bundle_topic')});
      final h = await _pump(
        tester,
        store,
        const NewsTopicScreen(topicId: 'fed_rates'),
        tier: SubscriptionTier.free,
      );
      await tester.tap(find.text('news_feed_compare').first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        h.events.logged.any((e) => e.$2['source'] == PaywallSource.newsCompare),
        isTrue,
      );
    });
  });

  group('NewsVideoSheet', () {
    const video = NewsVideo(
      videoId: 'dQw4w9WgXcQ',
      title: 'Qué pasó hoy en los mercados',
      channel: 'Reuters',
      url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    );

    testWidgets('embeds the player and keeps "open on YouTube"', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeDailyBriefStore(),
        const Scaffold(body: NewsVideoSheet(video: video)),
      );
      expect(find.text('player:dQw4w9WgXcQ'), findsOneWidget);
      expect(find.text('news_video_open'), findsOneWidget);
    });

    testWidgets('player error falls back to the YouTube link', (tester) async {
      final launched = <Uri>[];
      await _pump(
        tester,
        FakeDailyBriefStore(),
        const Scaffold(body: NewsVideoSheet(video: video)),
        launched: launched,
      );
      await tester.tap(find.byKey(const Key('fake-player')));
      await tester.pump();
      expect(find.byKey(const Key('fake-player')), findsNothing);
      expect(find.text('news_video_unavailable'), findsOneWidget);
      await tester.tap(find.text('news_video_open'));
      await tester.pump();
      expect(launched.single.host, 'www.youtube.com');
    });

    testWidgets('an id that cannot be embedded goes straight to the link', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeDailyBriefStore(),
        const Scaffold(
          body: NewsVideoSheet(
            video: NewsVideo(
              videoId: 'bad',
              title: 't',
              channel: 'c',
              url: 'https://www.youtube.com/watch?v=bad',
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('fake-player')), findsNothing);
      expect(find.text('news_video_unavailable'), findsOneWidget);
    });
  });
}
