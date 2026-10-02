import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_relevance_ranker.dart';
import 'package:portfolio_assistant/infraestructure/repositories/google_news_rss_repository_impl.dart';

void main() {
  final body = File('test/fixtures/news/google_news_nvda.xml').readAsStringSync();

  test('parses items in feed order, strips the " - Source" suffix', () {
    final items = GoogleNewsRssRepositoryImpl.parse(body, 'NVDA');
    expect(items, hasLength(5)); // el item sin fecha se descarta
    expect(
      items.first.headline,
      'Nvidia sets biggest-ever buyback plan as AI chip competition weighs',
    );
    expect(items.first.source, 'Reuters');
    expect(items.first.sourceDomain, 'reuters.com');
    expect(items.first.publishedAt, DateTime.utc(2026, 9, 28, 11, 6));
    expect(items.first.imageUrl, isNull);
    expect(items.first.summary, isEmpty);
  });

  test('builds complementary queries from the company name', () {
    expect(
      GoogleNewsRssRepositoryImpl.searchQueries('NVDA', 'NVIDIA Corp'),
      ['"NVIDIA"', 'NVIDIA stock'],
    );
    expect(
      GoogleNewsRssRepositoryImpl.searchQueries('KO', 'Coca-Cola Co'),
      ['"Coca-Cola"', 'Coca-Cola stock'],
    );
    expect(GoogleNewsRssRepositoryImpl.searchQueries('VOO', null), [
      'VOO stock',
    ]);
  });

  test('interleaves feeds by rank without repeating urls', () {
    final items = GoogleNewsRssRepositoryImpl.parse(body, 'NVDA');
    final merged = GoogleNewsRssRepositoryImpl.interleave([
      [items[0], items[1]],
      [items[1], items[2]],
    ]);
    expect(merged.map((i) => i.source), ['Reuters', 'WSJ', 'CNBC']);
  });

  test('ranked: one headline per event, off-topic noise dropped', () {
    final ranked = NewsRelevanceRanker.rank(
      GoogleNewsRssRepositoryImpl.parse(body, 'NVDA'),
      ticker: 'NVDA',
      companyName: 'NVIDIA Corp',
      limit: 3,
      feedIsRanked: true,
      now: DateTime.utc(2026, 9, 29, 12),
    );
    // Reuters, WSJ y CNBC cubren la misma recompra (Reuters y WSJ no
    // comparten palabras: los une CNBC) → queda una; la de Motley Fool no
    // menciona a Nvidia.
    expect(ranked.map((i) => i.source), ['Reuters', 'bloomberg.com']);
  });

  test('recent news uses when:7d; a closed week uses after/before', () {
    expect(
      GoogleNewsRssRepositoryImpl.withTimeWindow('"NVIDIA"', null),
      '"NVIDIA" when:7d',
    );
    expect(
      GoogleNewsRssRepositoryImpl.withTimeWindow('NVIDIA stock', (
        from: DateTime(2026, 9, 21),
        to: DateTime(2026, 9, 26),
      )),
      'NVIDIA stock after:2026-09-21 before:2026-09-26',
    );
  });
}
