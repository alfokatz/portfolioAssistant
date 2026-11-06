// Sync del widget con novedades: pide con el plan cargado, usa la caché si
// falla, apaga todo con news_provider != v2, no escribe ticker en los
// eventos y borra todo al cerrar sesión.
// Correr: flutter test test/features/home_widget/providers
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/company_news_repository.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/assistant/data/market/earnings_fetcher.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_items_cache.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_items_repository.dart';
import 'package:portfolio_assistant/features/home_widget/providers/home_widget_sync_provider.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../home_widget_test_helpers.dart';

class _Events extends ProductEvents {
  _Events() : super(client: () => null, prefs: () => null);
  final logged = <(ProductEvent, Map<String, Object?>)>[];

  @override
  void log(ProductEvent event, [Map<String, Object?> props = const {}]) =>
      logged.add((event, props));
}

class _News implements CompanyNewsRepository {
  int calls = 0;
  bool fail = false;

  @override
  Future<Either<HttpError, List<CompanyNewsItem>>> getRecentNews(
    String ticker, {
    int limit = 3,
    DateTime? from,
    DateTime? to,
  }) async {
    calls++;
    if (fail) return Left(HttpError(code: 'headlines_500'));
    return Right([
      CompanyNewsItem(
        ticker: ticker,
        headline: 'Novedad de $ticker',
        summary: '',
        url: 'https://example.com/$ticker',
        source: 'Fuente Ejemplo',
        publishedAt: _now.subtract(const Duration(hours: 2)),
      ),
    ]);
  }
}

class _NoEarnings implements EarningsSource {
  @override
  Future<Map<String, Object?>> fetch(List<String> tickers) async => {
    'status': 'empty',
    'earnings': <String, Object?>{},
  };
}

final _now = DateTime(2026, 11, 5, 12);

HomeState _home() {
  final p = Position(
    id: '1',
    ticker: 'NVDA',
    quantity: 10,
    purchasePrice: 100,
    purchaseDate: DateTime(2026, 10, 1),
  );
  return HomeState(
    loading: false,
    summary: PortfolioCalculator.summarize([
      PortfolioCalculator.valuate(position: p, currentPrice: 120),
    ]),
    history: const [],
  );
}

Future<List<PriceCandle>> _candles(String t) async => [
  PriceCandle(date: DateTime(2026, 11, 4), close: 110),
  PriceCandle(date: DateTime(2026, 11, 5), close: 120),
];

void main() {
  late FakeHomeWidgetStore store;
  late _Events events;
  late SharedPreferences prefs;
  late _News news;
  late HomeWidgetSyncController c;
  SubscriptionTier? tier;
  var v2 = true;
  var teasers = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = FakeHomeWidgetStore();
    events = _Events();
    news = _News();
    tier = SubscriptionTier.premium;
    v2 = true;
    teasers = false;
    c = HomeWidgetSyncController(
      store: store,
      prefs: prefs,
      events: events,
      scheduler: FakeScheduler(),
      loadTexts: loadRealTexts,
      loadCandles: _candles,
      currentUserId: () => 'uid-1',
      amountsHidden: () => false,
      initialLang: 'es',
      now: () => _now,
      items: WidgetItemsRepository(
        news: news,
        earnings: _NoEarnings(),
        prefs: prefs,
      ),
      newsV2Enabled: () async => v2,
      currentTier: () => tier,
      teasersEnabled: () async => teasers,
    );
  });

  tearDown(() => c.dispose());

  test('premium: writes the news of the top positions', () async {
    c.onHome(null, _home());
    await c.flush();
    expect(_news(store.last).single['tag'], 'NVDA');
    expect(news.calls, 1);
  });

  test('a second write inside 30 minutes does not ask again', () async {
    c.onHome(null, _home());
    await c.flush();
    c.onLanguage('en');
    await c.flush();
    expect(news.calls, 1);
    expect(store.last['lang'], 'en');
    expect(_news(store.last), hasLength(1));
  });

  test('plan not loaded yet: no request, the snapshot has no items', () async {
    tier = null;
    c.onHome(null, _home());
    await c.flush();
    expect(news.calls, 0);
    expect(_news(store.last), isEmpty);
  });

  test('the plan arriving later triggers the request', () async {
    tier = null;
    c.onHome(null, _home());
    await c.flush();
    tier = SubscriptionTier.gold;
    c.onTierChanged();
    await c.flush();
    expect(news.calls, 1);
    expect(_news(store.last), isNotEmpty);
  });

  test('a failure keeps what was cached and never errors', () async {
    c.onHome(null, _home());
    await c.flush();
    // Vence el freno y falla el servidor.
    await prefs.setString(
      WidgetItemsCache.key,
      prefs
          .getString(WidgetItemsCache.key)!
          .replaceAll(
            '"checked_at":${_now.toUtc().millisecondsSinceEpoch}',
            '"checked_at":${_now.subtract(const Duration(hours: 2)).toUtc().millisecondsSinceEpoch}',
          ),
    );
    news.fail = true;
    c.onLanguage('en');
    await c.flush();
    expect(news.calls, 2);
    expect(_news(store.last), hasLength(1));
  });

  test(
    'news_provider other than v2: no items, no requests, cache cleared',
    () async {
      c.onHome(null, _home());
      await c.flush();
      v2 = false;
      c.onLanguage('en');
      await c.flush();
      expect(_news(store.last), isEmpty);
      expect(prefs.getString(WidgetItemsCache.key), isNull);
    },
  );

  test('free with the flag on: android teaser without number', () async {
    tier = SubscriptionTier.free;
    teasers = true;
    store.platformName = 'android';
    c.onHome(null, _home());
    await c.flush();
    final teaser = _teasers(store.last).single;
    final seg = (teaser['segments']! as List).first as Map;
    expect(seg['title'], 'Noticias de tu cartera · Premium');
  });

  test('free on ios without counts: no teaser (phase 2)', () async {
    tier = SubscriptionTier.free;
    teasers = true;
    c.onHome(null, _home());
    await c.flush();
    expect(_teasers(store.last), isEmpty);
  });

  test('hiding amounts keeps the items (scrub on stored snapshot)', () async {
    c.onHome(null, _home());
    await c.flush();
    expect(_news(store.last), isNotEmpty);
    await store.scrubStoredPositions();
    expect((store.last['v2'] as Map)['positions_hidden'], true);
    // Con posiciones ocultas quedan los ítems, sin ticker ni texto.
    expect(_news(store.last), isNotEmpty);
    expect(_news(store.last).first.containsKey('tag'), isFalse);
  });

  test(
    'sign out clears items cache, render log and writes signed_out',
    () async {
      c.onHome(null, _home());
      await c.flush();
      store.renderLog = {
        'large': {'at': 5},
      };
      c.onSignedOut();
      await c.flush();
      expect(prefs.getString(WidgetItemsCache.key), isNull);
      expect(store.renderLog, isNull);
      expect(store.last['state'], 'signed_out');
      expect(_news(store.last), isEmpty);
    },
  );

  group('widget_items_rendered', () {
    test('one per size, only newer than the last logged, no ticker', () async {
      store.renderLog = {
        'medium': {'at': 100, 'news': 1, 'earnings': 0, 'teaser': 'none'},
        'large': {'at': 200, 'news': 2, 'earnings': 1, 'teaser': 'news'},
      };
      await c.reportItemsRendered(tier: SubscriptionTier.gold);
      final logged = [
        for (final (e, p) in events.logged)
          if (e == ProductEvent.widgetItemsRendered) p,
      ];
      expect(logged, hasLength(2));
      expect(logged.last, {
        'size': 'large',
        'news_count': 2,
        'earnings_count': 1,
        'insight_count': 0,
        'mover_count': 0,
        'biggest_count': 0,
        'live_count': 0,
        'teaser': 'news',
        'tier': 'gold',
        'positions_hidden': false,
        'platform': 'ios',
      });
      expect(prefs.getInt(WidgetItemsCache.renderLoggedKey), 200);

      events.logged.clear();
      await c.reportItemsRendered(tier: SubscriptionTier.gold);
      expect(events.logged, isEmpty);

      store.renderLog = {
        'large': {'at': 300, 'news': 1, 'earnings': 0, 'teaser': 'weird'},
      };
      await c.reportItemsRendered(tier: SubscriptionTier.gold);
      expect(events.logged.single.$2['teaser'], 'none');
    });

    test('v2 render log: counts by kind, line and shown item', () async {
      store.renderLog = {
        'small': {'at': 10, 'line': 'insight', 'live': 3},
        'medium': {
          'at': 11,
          'shown_kind': 'earnings',
          'shown_prio': 1,
          'kinds': {'earnings': 1, 'insight': 1, 'mover': 1},
          'live': 3,
        },
      };
      await c.reportItemsRendered(tier: SubscriptionTier.gold);
      final logged = [
        for (final (e, p) in events.logged)
          if (e == ProductEvent.widgetItemsRendered) p,
      ];
      expect(logged.first['line_kind'], 'insight');
      expect(logged.first.containsKey('shown_kind'), isFalse);
      expect(logged.last['shown_kind'], 'earnings');
      expect(logged.last['shown_prio'], 1);
      expect(logged.last['insight_count'], 1);
      expect(logged.last['mover_count'], 1);
      expect(logged.last['live_count'], 3);
      expect(logged.last.containsKey('line_kind'), isFalse);
    });

    test('widget_feed_advanced logs the taps since the last time', () async {
      store.renderLog = {
        'medium': {'at': 1, 'next_taps': 4},
      };
      await c.reportItemsRendered();
      List<Map<String, Object?>> advanced() => [
        for (final (e, p) in events.logged)
          if (e == ProductEvent.widgetFeedAdvanced) p,
      ];
      expect(advanced().single, {
        'platform': 'ios',
        'size': 'medium',
        'taps': 4,
      });

      events.logged.clear();
      await c.reportItemsRendered();
      expect(advanced(), isEmpty);

      store.renderLog = {
        'medium': {'at': 2, 'next_taps': 6},
      };
      await c.reportItemsRendered();
      expect(advanced().single['taps'], 2);

      // El contador volvió a cero (render log borrado): se reancla sin log.
      events.logged.clear();
      store.renderLog = {
        'medium': {'at': 3, 'next_taps': 1},
      };
      await c.reportItemsRendered();
      expect(advanced(), isEmpty);
      expect(
        prefs.getInt(HomeWidgetSyncController.nextTapsLoggedKey),
        1,
      );
    });

    test('without a render log nothing is logged', () async {
      await c.reportItemsRendered();
      expect(events.logged, isEmpty);
    });
  });

  test('no event carries a ticker or a headline', () async {
    c.onHome(null, _home());
    store.renderLog = {
      'medium': {'at': 9, 'news': 1},
    };
    await c.flush();
    await c.reportItemsRendered(tier: SubscriptionTier.premium);
    final text = events.logged.map((e) => e.$2.toString()).join();
    expect(text, isNot(contains('NVDA')));
    expect(text, isNot(contains('Novedad')));
  });
}

/// Novedades del feed v2 (noticias y resultados).
List<Map<Object?, Object?>> _news(Map<String, Object?> snapshot) => [
  for (final item in ((snapshot['v2'] as Map?)?['feed'] as List?) ?? const [])
    if (item is Map && (item['kind'] == 'news' || item['kind'] == 'earnings'))
      item,
];

/// Avisos del plan siguiente en el feed v2.
List<Map<Object?, Object?>> _teasers(Map<String, Object?> snapshot) => [
  for (final item in ((snapshot['v2'] as Map?)?['feed'] as List?) ?? const [])
    if (item is Map && item['kind'] == 'teaser') item,
];
