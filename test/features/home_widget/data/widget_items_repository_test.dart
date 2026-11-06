// WidgetItemsRepository: freno de 30 min, caché de 12 h de las fechas de
// resultados, falla que mantiene la caché, plan_required sin error, y la
// caché privada por usuario (se borra al cerrar sesión).
// Correr: flutter test test/features/home_widget/data
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/company_news_repository.dart';
import 'package:portfolio_assistant/features/assistant/data/market/earnings_fetcher.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_items_cache.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_items_repository.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_items_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNews implements CompanyNewsRepository {
  int calls = 0;
  String? failWith;
  final requested = <String>[];
  DateTime? lastFrom;
  DateTime? lastTo;
  late DateTime now;

  @override
  Future<Either<HttpError, List<CompanyNewsItem>>> getRecentNews(
    String ticker, {
    int limit = 3,
    DateTime? from,
    DateTime? to,
  }) async {
    calls++;
    requested.add(ticker);
    lastFrom = from;
    lastTo = to;
    if (failWith != null) return Left(HttpError(code: failWith!));
    return Right([
      CompanyNewsItem(
        ticker: ticker,
        headline: 'Novedad de $ticker',
        summary: '',
        url: 'https://example.com/$ticker',
        source: 'Fuente Ejemplo',
        publishedAt: now.subtract(const Duration(hours: 2)),
      ),
    ]);
  }
}

class _FakeEarnings implements EarningsSource {
  int calls = 0;
  bool fail = false;
  final fetched = <List<String>>[];

  @override
  Future<Map<String, Object?>> fetch(List<String> tickers) async {
    calls++;
    fetched.add(tickers);
    if (fail) return {'status': 'failed', 'earnings': {}};
    return {
      'status': 'ok',
      'earnings': {
        for (final t in tickers)
          t: {
            'next_report': {'date': '2026-11-07', 'estimated': true},
          },
      },
    };
  }
}

class _Counts implements WidgetCountsClient {
  WidgetTeaserCounts? value;
  int calls = 0;

  @override
  Future<WidgetTeaserCounts?> fetch(
    List<String> tickers, {
    DateTime? now,
  }) async {
    calls++;
    return value;
  }
}

const _holdings = [
  WidgetHolding(ticker: 'AAA', marketValue: 300),
  WidgetHolding(ticker: 'BBB', marketValue: 200),
  WidgetHolding(ticker: 'BTC', marketValue: 900, isCrypto: true),
];

final _t0 = DateTime(2026, 11, 5, 12);

void main() {
  late SharedPreferences prefs;
  late _FakeNews news;
  late _FakeEarnings earnings;
  late _Counts counts;
  late WidgetItemsRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    news = _FakeNews()..now = _t0;
    earnings = _FakeEarnings();
    counts = _Counts();
    repo = WidgetItemsRepository(
      news: news,
      earnings: earnings,
      prefs: prefs,
      counts: counts,
    );
  });

  WidgetItemsRequest req({
    DateTime? now,
    SubscriptionTier tier = SubscriptionTier.gold,
    List<WidgetHolding> holdings = _holdings,
    bool teasers = false,
    bool force = false,
    String uid = 'u1',
  }) => WidgetItemsRequest(
    uid: uid,
    holdings: holdings,
    tier: tier,
    teasersEnabled: teasers,
    platform: WidgetPlatform.android,
    now: now ?? _t0,
    force: force,
  );

  test('gold: news for the top tickers (no crypto) and earnings dates', () async {
    final entry = await repo.refresh(req());
    expect(news.requested, ['AAA', 'BBB']);
    expect(entry.items.map((i) => i.kind).toSet(), {'news', 'earnings'});
    // El día completo hasta mañana, para compartir caché del servidor.
    expect(news.lastFrom, _t0.subtract(const Duration(hours: 48)));
    expect(news.lastTo, _t0.add(const Duration(days: 1)));
    // La URL vive solo en la caché privada.
    expect(entry.items.firstWhere((i) => i.isNews).url, startsWith('https://'));
  });

  test('premium: news only, never asks for earnings', () async {
    final entry = await repo.refresh(req(tier: SubscriptionTier.premium));
    expect(entry.items.every((i) => i.isNews), isTrue);
    expect(earnings.calls, 0);
  });

  test('free: asks nothing (phase 1)', () async {
    final entry = await repo.refresh(req(tier: SubscriptionTier.free));
    expect(news.calls, 0);
    expect(earnings.calls, 0);
    expect(entry.items, isEmpty);
    expect(entry.itemsSection, isFalse);
  });

  test('30 minute brake: no new requests, then it asks again', () async {
    await repo.refresh(req());
    final calls = news.calls;
    await repo.refresh(req(now: _t0.add(const Duration(minutes: 29))));
    expect(news.calls, calls);
    await repo.refresh(req(now: _t0.add(const Duration(minutes: 30))));
    expect(news.calls, calls * 2);
  });

  test('force skips the brake', () async {
    await repo.refresh(req());
    final calls = news.calls;
    await repo.refresh(req(force: true));
    expect(news.calls, calls * 2);
  });

  test('a different top 5 or tier asks again', () async {
    await repo.refresh(req());
    final calls = news.calls;
    await repo.refresh(
      req(
        holdings: const [WidgetHolding(ticker: 'ZZZ', marketValue: 5)],
        now: _t0.add(const Duration(minutes: 1)),
      ),
    );
    expect(news.calls, greaterThan(calls));
    final after = news.calls;
    await repo.refresh(
      req(
        tier: SubscriptionTier.premium,
        holdings: const [WidgetHolding(ticker: 'ZZZ', marketValue: 5)],
        now: _t0.add(const Duration(minutes: 2)),
      ),
    );
    expect(news.calls, greaterThan(after));
  });

  test('earnings dates are cached 12 hours per ticker', () async {
    await repo.refresh(req());
    expect(earnings.calls, 1);
    await repo.refresh(req(now: _t0.add(const Duration(hours: 1))));
    expect(earnings.calls, 1);
    await repo.refresh(req(now: _t0.add(const Duration(hours: 12, minutes: 1))));
    expect(earnings.calls, 2);
  });

  test('a failure throws and keeps the previous cache', () async {
    final first = await repo.refresh(req());
    news.failWith = 'headlines_500';
    await expectLater(
      repo.refresh(req(now: _t0.add(const Duration(hours: 1)))),
      throwsA(isA<WidgetItemsFailure>()),
    );
    final kept = repo.cached('u1')!;
    expect(kept.checkedAt.isAtSameMomentAs(first.checkedAt), isTrue);
    expect(kept.items, hasLength(first.items.length));
  });

  test('earnings failure throws too', () async {
    earnings.fail = true;
    await expectLater(repo.refresh(req()), throwsA(isA<WidgetItemsFailure>()));
    expect(repo.cached('u1'), isNull);
  });

  test('plan_required from the server: zero items, never an error', () async {
    news.failWith = 'plan_required';
    final entry = await repo.refresh(req(tier: SubscriptionTier.premium));
    expect(entry.items, isEmpty);
  });

  test('the cache is per user', () async {
    await repo.refresh(req());
    expect(repo.cached('u1'), isNotNull);
    expect(repo.cached('u2'), isNull);
  });

  test('clear removes items, earnings cache and render log mark', () async {
    await repo.refresh(req());
    await prefs.setInt(WidgetItemsCache.renderLoggedKey, 5);
    await repo.cache.clear();
    expect(prefs.getString(WidgetItemsCache.key), isNull);
    expect(prefs.getString(WidgetItemsCache.earningsKey), isNull);
    expect(prefs.getInt(WidgetItemsCache.renderLoggedKey), isNull);
  });

  test('teaser counts only when the flag is on, and the client may fail', () async {
    await repo.refresh(req(tier: SubscriptionTier.free));
    expect(counts.calls, 0);
    counts.value = const WidgetTeaserCounts(news48: 2, news24: 1);
    final entry = await repo.refresh(
      req(tier: SubscriptionTier.free, teasers: true),
    );
    expect(counts.calls, 1);
    expect(entry.teaser?.count, 2);
  });

  test('default counts client (phase 1) gives the number-less teaser', () async {
    final phase1 = WidgetItemsRepository(
      news: news,
      earnings: earnings,
      prefs: prefs,
    );
    final entry = await phase1.refresh(
      req(tier: SubscriptionTier.free, teasers: true),
    );
    expect(entry.teaser?.kind, 'news');
    expect(entry.teaser?.count, isNull);
  });

  test('cache entry round trip keeps live items only on request', () async {
    final entry = await repo.refresh(req());
    final read = repo.cached('u1')!;
    expect(read.items.length, entry.items.length);
    expect(read.liveItems(_t0.add(const Duration(days: 3))), isEmpty);
  });
}
