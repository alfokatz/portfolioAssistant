import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_relevance_ranker.dart';

CompanyNewsItem _n(String headline, {String source = 'Reuters'}) =>
    CompanyNewsItem(
      ticker: 'VOO',
      headline: headline,
      summary: '',
      url: 'https://x/${headline.hashCode}',
      source: source,
      publishedAt: DateTime.utc(2026, 9, 24),
    );

void main() {
  test('drops evergreen, SEO, comparisons, ratings and clickbait (real '
      'headlines the old report showed)', () {
    for (final (headline, source) in [
      ('VOO Top Holdings List & Exposure', 'ETF Database'),
      ('Is VOO or VTI the Better Long-Term Investment?', 'Yahoo Finance'),
      ('VOO vs. SPY: Which S&P 500 ETF Wins', 'Yahoo Finance'),
      ('Amazon Could Be 48% Undervalued', 'Simply Wall St'),
      ('3 Reasons to Buy Amazon Stock Now', 'Yahoo Finance'),
      ('Best ETFs to Buy for 2027', 'Yahoo Finance'),
      ('Amazon stock price prediction for 2030', 'Yahoo Finance'),
      ('Here’s why Nvidia keeps climbing', 'Yahoo Finance'),
      ('Is It Time to Buy Microsoft Stock?', 'Yahoo Finance'),
      ('Apple shares rise after record iPhone preorders', 'The Motley Fool'),
    ]) {
      expect(
        NewsRelevanceRanker.isLowQuality(_n(headline, source: source)),
        isTrue,
        reason: headline,
      );
    }
  });

  test('keeps real news of the week', () {
    for (final headline in [
      'Amazon shares fall as AWS growth slows',
      'Vanguard cuts fees on S&P 500 ETF',
      'Microsoft faces EU antitrust probe over cloud deals',
      'Apple shares rise after record iPhone preorders',
    ]) {
      expect(
        NewsRelevanceRanker.isLowQuality(_n(headline)),
        isFalse,
        reason: headline,
      );
    }
  });

  test('only the strict mode (weekly report) filters; the chat keeps its '
      'behavior', () {
    final items = [
      _n('VOO Top Holdings List & Exposure'),
      _n('Vanguard cuts fees on VOO'),
    ];
    final chat = NewsRelevanceRanker.rank(items, ticker: 'VOO', limit: 5);
    final report = NewsRelevanceRanker.rank(
      items,
      ticker: 'VOO',
      limit: 5,
      strict: true,
    );
    expect(chat, hasLength(2));
    expect(report.map((i) => i.headline), ['Vanguard cuts fees on VOO']);
  });
}
