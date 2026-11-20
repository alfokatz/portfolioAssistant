// WidgetItemsSelector: qué entra en "Novedades de tu cartera" (top 5 sin
// cripto, resultados primero, noticias de 48 h, filtro de recomendación,
// avisos por plan y plataforma).
// Correr: flutter test test/features/home_widget/domain
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_items_selector.dart';

final _now = DateTime(2026, 11, 5, 12);

const _holdings = [
  WidgetHolding(ticker: 'AAA', marketValue: 600),
  WidgetHolding(ticker: 'BBB', marketValue: 500),
  WidgetHolding(ticker: 'CCC', marketValue: 400),
  WidgetHolding(ticker: 'DDD', marketValue: 300),
  WidgetHolding(ticker: 'EEE', marketValue: 200),
  WidgetHolding(ticker: 'FFF', marketValue: 100),
  WidgetHolding(ticker: 'BTC', marketValue: 9000, isCrypto: true),
];

CompanyNewsItem _news(
  String ticker,
  String headline, {
  Duration age = const Duration(hours: 2),
}) => CompanyNewsItem(
  ticker: ticker,
  headline: headline,
  summary: '',
  url: 'https://example.com/$ticker/${headline.hashCode}',
  source: 'Fuente Ejemplo',
  publishedAt: _now.subtract(age),
);

WidgetItemsSelection _select({
  List<WidgetHolding> holdings = _holdings,
  List<CompanyNewsItem> news = const [],
  List<WidgetEarningsDate> earnings = const [],
  SubscriptionTier tier = SubscriptionTier.gold,
  bool teasers = false,
  WidgetTeaserCounts? counts,
  WidgetPlatform platform = WidgetPlatform.android,
}) => WidgetItemsSelector.select(
  holdings: holdings,
  news: news,
  earnings: earnings,
  tier: tier,
  teasersEnabled: teasers,
  teaserCounts: counts,
  platform: platform,
  now: _now,
);

List<String> _tickers(WidgetItemsSelection s) => [
  for (final i in s.items) i.ticker,
];

void main() {
  group('universe', () {
    test('top 5 by value, no crypto, ties alphabetical', () {
      final top = WidgetItemsSelector.universe([
        ..._holdings,
        const WidgetHolding(ticker: 'ZZZ', marketValue: 200),
        const WidgetHolding(ticker: 'ZERO', marketValue: 0),
      ]);
      expect([for (final h in top) h.ticker], [
        'AAA',
        'BBB',
        'CCC',
        'DDD',
        'EEE',
      ]);
    });

    test('news outside the top 5 or about crypto is ignored', () {
      final s = _select(
        news: [_news('FFF', 'Sexta noticia'), _news('BTC', 'Cripto sube')],
      );
      expect(s.items, isEmpty);
    });
  });

  group('news', () {
    test('48 hour window edges', () {
      final s = _select(
        news: [
          _news('AAA', 'Dentro', age: const Duration(hours: 47, minutes: 59)),
          _news('BBB', 'Fuera', age: const Duration(hours: 48, minutes: 1)),
        ],
      );
      expect(_tickers(s), ['AAA']);
    });

    test('future by more than 5 minutes is dropped', () {
      final s = _select(
        news: [
          _news('AAA', 'Casi', age: const Duration(minutes: -4)),
          _news('BBB', 'Futuro', age: const Duration(minutes: -6)),
        ],
      );
      expect(_tickers(s), ['AAA']);
    });

    test('one per ticker (the most recent), ordered by weight', () {
      final s = _select(
        news: [
          _news('BBB', 'B vieja', age: const Duration(hours: 9)),
          _news('BBB', 'B nueva', age: const Duration(hours: 1)),
          _news('AAA', 'A única', age: const Duration(hours: 20)),
        ],
      );
      expect(_tickers(s), ['AAA', 'BBB']);
      expect((s.items[1] as SelectedNews).news.headline, 'B nueva');
    });

    test('same headline (normalized) keeps the heavier position', () {
      final s = _select(
        news: [
          _news('BBB', 'Mercados: suben las tasas!'),
          _news('AAA', 'mercados suben las tasas'),
        ],
      );
      expect(_tickers(s), ['AAA']);
    });

    test('ties in weight go to the most recent', () {
      final s = _select(
        holdings: const [
          WidgetHolding(ticker: 'AAA', marketValue: 100),
          WidgetHolding(ticker: 'BBB', marketValue: 100),
        ],
        news: [
          _news('AAA', 'A', age: const Duration(hours: 5)),
          _news('BBB', 'B', age: const Duration(hours: 1)),
        ],
      );
      expect(_tickers(s), ['BBB', 'AAA']);
    });

    test('capped at 4 items', () {
      final s = _select(
        news: [
          for (final t in ['AAA', 'BBB', 'CCC', 'DDD', 'EEE'])
            _news(t, 'Titular de $t'),
        ],
      );
      expect(s.items, hasLength(4));
    });
  });

  group('recommendation filter', () {
    for (final headline in [
      '3 stocks to buy before the year ends',
      'Should you sell NVDA?',
      'Should you buy AAA now',
      'Time to buy AAA',
      'Best dividend stocks to buy this year',
      'This is a must-buy',
      'Buy now, ask later',
      'Comprá AAA antes de que suba',
      'Aprovechá la baja',
      'Vendé todo',
    ]) {
      test('drops "$headline"', () {
        expect(WidgetItemsSelector.isRecommendation(headline), isTrue);
        expect(_select(news: [_news('AAA', headline)]).items, isEmpty);
      });
    }

    for (final headline in [
      'Analyst upgrades NVDA to Buy',
      'AAA presenta resultados del trimestre',
      'Microsoft compra una empresa de videojuegos',
    ]) {
      test('keeps "$headline"', () {
        expect(WidgetItemsSelector.isRecommendation(headline), isFalse);
        expect(_select(news: [_news('AAA', headline)]).items, hasLength(1));
      });
    }

    test('falls back to the next article of the same ticker', () {
      final s = _select(
        news: [
          _news('AAA', 'Should you buy AAA?', age: const Duration(hours: 1)),
          _news('AAA', 'AAA abre una planta', age: const Duration(hours: 3)),
        ],
      );
      expect((s.items.single as SelectedNews).news.headline, 'AAA abre una planta');
    });
  });

  group('earnings', () {
    test('only [today, today+6], date then weight, max 2, before news', () {
      final s = _select(
        earnings: [
          (ticker: 'AAA', date: DateTime(2026, 11, 7)),
          (ticker: 'BBB', date: DateTime(2026, 11, 6)),
          (ticker: 'CCC', date: DateTime(2026, 11, 6)),
          (ticker: 'DDD', date: DateTime(2026, 11, 11)),
          (ticker: 'EEE', date: DateTime(2026, 11, 12)),
          (ticker: 'FFF', date: DateTime(2026, 11, 6)),
        ],
        news: [_news('DDD', 'DDD novedad')],
      );
      expect(_tickers(s), ['BBB', 'CCC', 'DDD']);
      expect(s.items.first, isA<SelectedEarnings>());
      expect(s.items.last, isA<SelectedNews>());
    });

    test('yesterday is out, today is in', () {
      final s = _select(
        earnings: [
          (ticker: 'AAA', date: DateTime(2026, 11, 4)),
          (ticker: 'BBB', date: DateTime(2026, 11, 5)),
        ],
      );
      expect(_tickers(s), ['BBB']);
    });
  });

  group('plans', () {
    final news = [_news('AAA', 'Titular A')];
    final earnings = [(ticker: 'AAA', date: DateTime(2026, 11, 6))];

    test('free never gets items', () {
      final s = _select(
        tier: SubscriptionTier.free,
        news: news,
        earnings: earnings,
      );
      expect(s.items, isEmpty);
      expect(s.itemsSection, isFalse);
    });

    test('premium gets news, never earnings', () {
      final s = _select(
        tier: SubscriptionTier.premium,
        news: news,
        earnings: earnings,
      );
      expect(s.items.single, isA<SelectedNews>());
      expect(s.itemsSection, isTrue);
    });

    test('premium with no eligible ticker has no section', () {
      final s = _select(
        tier: SubscriptionTier.premium,
        holdings: const [
          WidgetHolding(ticker: 'BTC', marketValue: 10, isCrypto: true),
        ],
      );
      expect(s.itemsSection, isFalse);
    });

    test('gold gets both and never a teaser', () {
      final s = _select(
        news: news,
        earnings: earnings,
        teasers: true,
        counts: const WidgetTeaserCounts(news48: 3, earnings7: 3),
      );
      expect(s.items, hasLength(2));
      expect(s.teaser, isNull);
    });
  });

  group('teaser', () {
    test('android free without counts: no number', () {
      final s = _select(tier: SubscriptionTier.free, teasers: true);
      expect(s.teaser?.kind, 'news');
      expect(s.teaser?.count, isNull);
      expect(s.itemsSection, isTrue);
    });

    test('flag off: no teaser', () {
      final s = _select(tier: SubscriptionTier.free);
      expect(s.teaser, isNull);
      expect(s.itemsSection, isFalse);
    });

    test('ios without counts: no teaser', () {
      final s = _select(
        tier: SubscriptionTier.free,
        teasers: true,
        platform: WidgetPlatform.ios,
      );
      expect(s.teaser, isNull);
    });

    test('ios free with count', () {
      final s = _select(
        tier: SubscriptionTier.free,
        teasers: true,
        platform: WidgetPlatform.ios,
        counts: const WidgetTeaserCounts(news48: 2, news24: 1),
      );
      expect(s.teaser?.count, 2);
      expect(s.teaser?.medium, isTrue);
    });

    test('count zero: no teaser, even on android', () {
      final s = _select(
        tier: SubscriptionTier.free,
        teasers: true,
        counts: const WidgetTeaserCounts(news48: 0),
      );
      expect(s.teaser, isNull);
    });

    test('premium: earnings teaser only with a count', () {
      expect(
        _select(tier: SubscriptionTier.premium, teasers: true).teaser,
        isNull,
      );
      final s = _select(
        tier: SubscriptionTier.premium,
        teasers: true,
        counts: const WidgetTeaserCounts(earnings7: 2),
      );
      expect(s.teaser?.kind, 'earnings');
      expect(s.teaser?.count, 2);
    });

    test('the teaser counts in the 4 items of the large widget', () {
      final s = _select(
        tier: SubscriptionTier.premium,
        teasers: true,
        counts: const WidgetTeaserCounts(earnings7: 1),
        news: [
          for (final t in ['AAA', 'BBB', 'CCC', 'DDD'])
            _news(t, 'Titular de $t'),
        ],
      );
      expect(s.items, hasLength(3));
      expect(s.teaser, isNotNull);
    });
  });

  group('ids', () {
    test('are 8 hex and stable', () {
      final id = WidgetItemsSelector.newsId('aaa', 'https://x.com/a');
      expect(id, matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(WidgetItemsSelector.newsId('AAA', 'https://x.com/a'), id);
      expect(
        WidgetItemsSelector.earningsId('AAA', DateTime(2026, 11, 6)),
        isNot(id),
      );
    });

    test('FNV-1a reference value', () {
      // FNV-1a 32 de "a" = e40c292c
      expect(WidgetItemsSelector.itemId('a'), 'e40c292c');
    });
  });
}
