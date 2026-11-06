// refreshOnce (lógica del refresco de fondo, sin el plugin): sin uid, sin
// lotes, ticker caído, todos caídos y uid cambiado.
// Correr: flutter test test/features/home_widget/data
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_background_refresh.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_settings_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/data/home_portfolio_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../home_widget_test_helpers.dart';

final _now = DateTime(2026, 11, 5, 12);

Position _pos(String t, double q) => Position(
  id: t,
  ticker: t,
  quantity: q,
  purchasePrice: 100,
  purchaseDate: DateTime(2026, 10, 1),
);

Future<void> _cache(
  SharedPreferences prefs, {
  List<Position>? positions,
}) async {
  final list = positions ?? [_pos('AAA', 10), _pos('BBB', 1)];
  final summary = PortfolioCalculator.summarize([
    for (final p in list)
      PortfolioCalculator.valuate(position: p, currentPrice: 50),
  ]);
  await HomePortfolioCache(
    prefs: prefs,
    userId: () => 'uid-1',
  ).write(HomeSnapshot(summary: summary));
}

List<PriceCandle> _ok(double a, double b) => [
  PriceCandle(date: DateTime(2026, 11, 4), close: a),
  PriceCandle(date: DateTime(2026, 11, 5), close: b),
];

void main() {
  late SharedPreferences prefs;
  late FakeHomeWidgetStore store;

  Future<bool> run(Future<List<PriceCandle>> Function(String) load) =>
      refreshOnce(
        WidgetRefreshDeps(
          prefs: prefs,
          loadCandles: load,
          loadTexts: loadRealTexts,
          store: store,
          now: () => _now,
        ),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      WidgetPrefsKeys.ownerUid: 'uid-1',
      WidgetPrefsKeys.lang: 'en',
    });
    prefs = await SharedPreferences.getInstance();
    store = FakeHomeWidgetStore();
  });

  test('writes ready with new prices, in the saved language', () async {
    await _cache(prefs);
    final wrote = await run(
      (t) async => t == 'AAA' ? _ok(10, 12) : _ok(100, 90),
    );

    expect(wrote, isTrue);
    expect(store.last['state'], 'ready');
    expect(store.last['lang'], 'en');
    // 10*12 + 1*90
    expect(store.last['total_text'], r'$210.00');
    // +20 -10 = +10
    expect(store.last['change_text'], r'+$10.00');
    expect(
      store.last['phrase'],
      'Your portfolio is up today; AAA added the most.',
    );
  });

  test('respects the hidden amounts setting', () async {
    await _cache(prefs);
    await prefs.setBool(WidgetPrefsKeys.amountsHidden, true);
    await run((t) async => _ok(10, 12));
    expect(store.last.containsKey('total_text'), isFalse);
    expect(store.last['phrase'], isNot(contains('AAA')));
  });

  test('without owner uid it does nothing', () async {
    await _cache(prefs);
    await prefs.remove(WidgetPrefsKeys.ownerUid);
    expect(await run((t) async => _ok(1, 2)), isFalse);
    expect(store.writes, isEmpty);
  });

  test('without cached lots it does nothing', () async {
    expect(await run((t) async => _ok(1, 2)), isFalse);
    await _cache(prefs, positions: []);
    expect(await run((t) async => _ok(1, 2)), isFalse);
    expect(store.writes, isEmpty);
  });

  test('a failed ticker keeps its cached price and adds no movement', () async {
    await _cache(prefs);
    final wrote = await run((t) async {
      if (t == 'BBB') throw StateError('down');
      return _ok(10, 12);
    });
    expect(wrote, isTrue);
    // 10*12 + 1*50 (precio del caché)
    expect(store.last['total_text'], r'$170.00');
    expect(store.last['change_text'], r'+$20.00');
  });

  test('all tickers failing writes nothing', () async {
    await _cache(prefs);
    expect(await run((t) async => throw StateError('down')), isFalse);
    expect(await run((t) async => <PriceCandle>[]), isFalse);
    expect(store.writes, isEmpty);
  });

  test('owner changed while fetching: does not write', () async {
    await _cache(prefs);
    final wrote = await run((t) async {
      await prefs.remove(WidgetPrefsKeys.ownerUid);
      return _ok(10, 12);
    });
    expect(wrote, isFalse);
    expect(store.writes, isEmpty);
  });

  group('clearHomeWidgetForSignedOutLaunch', () {
    test(
      'writes signed_out, clears the owner and cancels the refresh',
      () async {
        final scheduler = FakeScheduler();
        await clearHomeWidgetForSignedOutLaunch(
          prefs: prefs,
          store: store,
          scheduler: scheduler,
          loadTexts: loadRealTexts,
          now: () => _now,
        );

        expect(prefs.getString(WidgetPrefsKeys.ownerUid), isNull);
        expect(scheduler.cancelled, 1);
        expect(store.last['state'], 'signed_out');
        expect(store.last['lang'], 'en');
        expect(store.last.containsKey('total_text'), isFalse);
      },
    );

    test('a failing store never throws', () async {
      store.failWrites = true;
      await clearHomeWidgetForSignedOutLaunch(
        prefs: prefs,
        store: store,
        scheduler: FakeScheduler(),
        loadTexts: loadRealTexts,
        now: () => _now,
      );
      expect(prefs.getString(WidgetPrefsKeys.ownerUid), isNull);
    });
  });
}
