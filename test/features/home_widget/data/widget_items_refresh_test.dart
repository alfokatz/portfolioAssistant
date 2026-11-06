// Refresco de fondo con novedades: rearma los ítems desde la caché privada
// sin red, descarta los vencidos y no incluye nada de otro usuario. Y el
// arranque sin sesión borra ítems, caché y render log.
// Correr: flutter test test/features/home_widget/data
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_background_refresh.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_items_cache.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_items_selector.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_settings_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/data/home_portfolio_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../home_widget_test_helpers.dart';

final _now = DateTime(2026, 11, 5, 12);

Future<void> _homeCache(SharedPreferences prefs) async {
  final p = Position(
    id: 'AAA',
    ticker: 'AAA',
    quantity: 10,
    purchasePrice: 100,
    purchaseDate: DateTime(2026, 10, 1),
  );
  final summary = PortfolioCalculator.summarize([
    PortfolioCalculator.valuate(position: p, currentPrice: 50),
  ]);
  await HomePortfolioCache(
    prefs: prefs,
    userId: () => 'uid-1',
  ).write(HomeSnapshot(summary: summary));
}

WidgetCachedItem _news(String ticker, Duration age) => WidgetCachedItem(
  id: 'aaaaaaa$ticker'.substring(0, 8),
  kind: 'news',
  ticker: ticker,
  headline: 'Novedad de $ticker',
  source: 'Fuente Ejemplo',
  url: 'https://example.com/$ticker',
  publishedAt: _now.subtract(age),
  expiresAt: _now.subtract(age).add(const Duration(hours: 48)),
);

Future<void> _entry(
  SharedPreferences prefs,
  List<WidgetCachedItem> items, {
  String uid = 'uid-1',
  SelectedTeaser? teaser,
  bool section = true,
  DateTime? planUntil,
}) => WidgetItemsCache(prefs).write(
  WidgetItemsCacheEntry(
    uid: uid,
    checkedAt: _now.subtract(const Duration(minutes: 40)),
    tier: 'premium',
    top: 'AAA',
    teasersEnabled: teaser != null,
    itemsSection: section,
    items: items,
    teaser: teaser,
    planUntil: planUntil,
  ),
);

List<PriceCandle> _candles() => [
  PriceCandle(date: DateTime(2026, 11, 4), close: 10),
  PriceCandle(date: DateTime(2026, 11, 5), close: 12),
];

void main() {
  late SharedPreferences prefs;
  late FakeHomeWidgetStore store;

  Future<bool> run() => refreshOnce(
    WidgetRefreshDeps(
      prefs: prefs,
      loadCandles: (_) async => _candles(),
      loadTexts: loadRealTexts,
      store: store,
      now: () => _now,
    ),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      WidgetPrefsKeys.ownerUid: 'uid-1',
      WidgetPrefsKeys.lang: 'es',
    });
    prefs = await SharedPreferences.getInstance();
    store = FakeHomeWidgetStore();
    await _homeCache(prefs);
  });

  group('refreshOnce with items', () {
    test(
      'rebuilds the items from the private cache, with no network',
      () async {
        await _entry(prefs, [_news('AAA', const Duration(hours: 3))]);
        expect(await run(), isTrue);

        final items = store.last['items']! as List;
        expect(items, hasLength(1));
        expect((items.single as Map)['headline'], 'Novedad de AAA');
        expect(store.last['items_section'], true);
        expect(
          store.last['items_checked_at'],
          _now
              .subtract(const Duration(minutes: 40))
              .toUtc()
              .millisecondsSinceEpoch,
        );
        expect(store.last.toString(), isNot(contains('https://')));
      },
    );

    test('drops expired items', () async {
      await _entry(prefs, [
        _news('AAA', const Duration(hours: 3)),
        _news('BBB', const Duration(hours: 49)),
      ]);
      await run();
      final items = store.last['items']! as List;
      expect(items.map((i) => (i as Map)['ticker']), ['AAA']);
    });

    test(
      'all expired: passes them so the native shows "all expired", not "no news"',
      () async {
        await _entry(prefs, [_news('AAA', const Duration(hours: 50))]);
        await run();
        final items = store.last['items']! as List;
        expect(items, hasLength(1));
        final expiresAt = (items.single as Map)['expires_at']! as int;
        expect(expiresAt, lessThan(_now.millisecondsSinceEpoch));
        expect(store.last['items_section'], true);
      },
    );

    test('past plan_until: paid items are not written again', () async {
      await _entry(prefs, [
        _news('AAA', const Duration(hours: 3)),
      ], planUntil: _now.subtract(const Duration(minutes: 1)));
      await run();
      expect(store.last.containsKey('items'), isFalse);
    });

    test('another user cache: no items at all', () async {
      await _entry(prefs, [
        _news('AAA', const Duration(hours: 3)),
      ], uid: 'otro');
      await run();
      expect(store.last.containsKey('items'), isFalse);
      expect(store.last.containsKey('items_section'), isFalse);
    });

    test('keeps the teaser', () async {
      await _entry(prefs, const [], teaser: const SelectedTeaser(kind: 'news'));
      store.platformName = 'android';
      await run();
      expect(
        (store.last['teaser']! as Map)['text'],
        'Noticias de tu cartera · Premium',
      );
    });

    test('hidden amounts: no amounts, items stay', () async {
      await _entry(prefs, [_news('AAA', const Duration(hours: 3))]);
      await prefs.setBool(WidgetPrefsKeys.amountsHidden, true);
      await run();
      expect(store.last.containsKey('total_text'), isFalse);
      expect(store.last['items'], hasLength(1));
    });

    test('without cache the snapshot is the v1 one', () async {
      await run();
      expect(store.last.containsKey('items'), isFalse);
    });
  });

  group('signed out launch', () {
    test('deletes items, caches and render log', () async {
      await _entry(prefs, [_news('AAA', const Duration(hours: 3))]);
      await prefs.setString(WidgetItemsCache.earningsKey, '{}');
      await prefs.setInt(WidgetItemsCache.renderLoggedKey, 1);
      store.renderLog = {
        'medium': {'at': 1, 'news': 1},
      };

      await clearHomeWidgetForSignedOutLaunch(
        prefs: prefs,
        store: store,
        scheduler: FakeScheduler(),
        loadTexts: loadRealTexts,
        now: () => _now,
      );

      expect(prefs.getString(WidgetItemsCache.key), isNull);
      expect(prefs.getString(WidgetItemsCache.earningsKey), isNull);
      expect(prefs.getInt(WidgetItemsCache.renderLoggedKey), isNull);
      expect(store.renderLog, isNull);
      expect(store.renderLogClears, 1);
      expect(store.last['state'], 'signed_out');
      expect(store.last.containsKey('items'), isFalse);
      expect(store.last.containsKey('teaser'), isFalse);
    });
  });
}
