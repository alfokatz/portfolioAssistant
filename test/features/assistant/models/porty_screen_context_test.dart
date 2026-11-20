// PortyScreenContext con una noticia (spec 2026-11-20 §3.10) y su guía en el
// contexto fijado. Correr: flutter test test/features/assistant/models
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/models/porty_screen_context.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/tools/portfolio_tools.dart';

void main() {
  test('the news travels in screen_context with only what the screen has', () {
    final brief = PortyScreenContext.newsItem(
      PortyNewsItem(
        title: 'Nvidia supera previsiones',
        source: 'Reuters',
        url: 'https://www.reuters.com/a',
        publishedAt: DateTime.utc(2026, 11, 20, 9),
        ticker: 'nvda',
      ),
    ).toBrief(turnsAgo: 0);
    expect(brief['screen'], 'news_item');
    expect(brief['news'], {
      'title': 'Nvidia supera previsiones',
      'source': 'Reuters',
      'url': 'https://www.reuters.com/a',
      'published_at': '2026-11-20T09:00:00.000Z',
      'ticker': 'NVDA',
    });
  });

  test('topic id, no http links and long titles are clipped', () {
    final news =
        PortyNewsItem(
          title: 'x' * 500,
          url: 'http://insecure.com/a',
          topicId: 'fed_rates',
        ).toBrief();
    expect((news['title']! as String).length, PortyNewsItem.maxTitleChars);
    expect(news.containsKey('url'), isFalse);
    expect(news['topic_id'], 'fed_rates');
  });

  test('daily brief screen has its own value', () {
    expect(
      const PortyScreenContext(PortyScreen.dailyBrief).toBrief(turnsAgo: 1),
      {'screen': 'daily_brief', 'turns_ago': 1},
    );
  });

  test('the news guidance is in the pinned context only when there is news',
      () {
    final withNews = AssistantOpenAiService.pinnedContextFor({
      PortfolioBrief.screenContextKey:
          const PortyScreenContext.newsItem(
            PortyNewsItem(title: 't'),
          ).toBrief(turnsAgo: 0),
    });
    expect(withNews, contains(AssistantOpenAiService.newsContextGuidance));
    expect(withNews, contains('never state causes, never advise'));
    expect(withNews, contains('compare_sources'));

    final without = AssistantOpenAiService.pinnedContextFor({
      PortfolioBrief.screenContextKey:
          const PortyScreenContext.position('AAPL').toBrief(turnsAgo: 0),
    });
    expect(without, isNot(contains('screen_context.news')));
    expect(without, contains(AssistantOpenAiService.screenContextGuidance));
  });
}
