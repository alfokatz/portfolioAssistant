import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_relevance_ranker.dart';

final _now = DateTime.utc(2026, 9, 29, 12);
const _yahooLogo =
    'https://s.yimg.com/rz/stage/p/yahoo_finance_en-US_h_p_finance_2.png';

CompanyNewsItem _item(
  String headline, {
  String summary = '',
  String source = 'Yahoo',
  int hoursAgo = 1,
  String? image = _yahooLogo,
}) => CompanyNewsItem(
  ticker: 'NVDA',
  headline: headline,
  summary: summary,
  url: 'https://example.com/${headline.hashCode}',
  source: source,
  publishedAt: _now.subtract(Duration(hours: hoursAgo)),
  imageUrl: image,
);

List<String> _rank(List<CompanyNewsItem> items, {int limit = 3}) =>
    NewsRelevanceRanker.rank(
      items,
      ticker: 'NVDA',
      companyName: 'NVIDIA Corp',
      limit: limit,
      now: _now,
    ).map((i) => i.headline).toList();

void main() {
  test('drops articles that never mention the company or ticker', () {
    final ranked = _rank([
      _item('Want \$1,000 a Month in Passive Income? This ETF Could Help'),
      _item('Elon Musk Can\'t Sell SpaceX Shares Until 2027'),
      _item('Nvidia Stock Is at Its Cheapest Valuation Since 2015'),
    ]);
    expect(ranked, ['Nvidia Stock Is at Its Cheapest Valuation Since 2015']);
  });

  test('matches the ticker only as a whole word', () {
    final ranked = NewsRelevanceRanker.rank(
      [_item('Kodak shares jump'), _item('KO raises its dividend')],
      ticker: 'KO',
      companyName: 'Coca-Cola Co',
      limit: 3,
      now: _now,
    );
    expect(ranked.map((i) => i.headline), ['KO raises its dividend']);
  });

  test('ranks headline mentions and trusted outlets above summary-only noise', () {
    final ranked = _rank([
      _item('Chip stocks slide', summary: 'Nvidia fell 2%.', hoursAgo: 1),
      _item('Nvidia board adds \$150B to buyback', source: 'CNBC', hoursAgo: 20),
      _item('Nvidia launches agent safety platform', hoursAgo: 3),
    ]);
    expect(ranked.first, 'Nvidia board adds \$150B to buyback');
    expect(ranked.last, 'Chip stocks slide');
  });

  test('caps each source and removes duplicated syndicated headlines', () {
    final ranked = _rank([
      _item('Nvidia news one'),
      _item('Nvidia news two'),
      _item('Nvidia news three'),
      _item('Nvidia news one', source: 'Benzinga'),
      _item('NVDA options heat up', source: 'Benzinga'),
    ], limit: 5);
    expect(ranked.where((h) => h == 'Nvidia news one'), hasLength(1));
    // Yahoo tope 2 ('three' queda afuera); el duplicado de Benzinga no cuenta.
    expect(ranked, ['Nvidia news one', 'Nvidia news two', 'NVDA options heat up']);
  });

  test('strips a placeholder image repeated across the batch', () {
    final ranked = NewsRelevanceRanker.rank(
      [
        _item('Nvidia a'),
        _item('Nvidia b'),
        _item('Nvidia c', source: 'CNBC'),
        _item('Nvidia d', source: 'Reuters', image: 'https://img.example/d.jpg'),
      ],
      ticker: 'NVDA',
      companyName: 'NVIDIA Corp',
      limit: 4,
      now: _now,
    );
    final images = {for (final i in ranked) i.headline: i.imageUrl};
    expect(images['Nvidia a'], isNull);
    expect(images['Nvidia d'], 'https://img.example/d.jpg');
  });
}
