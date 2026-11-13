import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/utils/answer_sources.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_answer_review.dart';
import 'package:portfolio_assistant/features/assistant/utils/news_card_items.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

/// get_news sin titulares (la fuente no respondió) pero con la búsqueda web
/// ok: el caso de "¿qué noticias hay de NVDA?" (2026-11-14).
const _noHeadlines = ToolCallRecord(
  name: 'get_news',
  args: {
    'tickers': ['NVDA'],
  },
  result: {
    'status': 'ok',
    'news': [],
    'as_of': '2026-11-14T13:05:00Z',
    'context': {
      'status': 'ok',
      'summary': ['(2026-11-12): Jensen Huang renunció como CEO.'],
      'sources': [
        {
          'title': 'Nvidia ceo jensen huang resigns',
          'url':
              'https://www.cnbc.com/2026/11/12/nvidia-ceo-jensen-huang-resigns.html',
          'source': 'CNBC',
        },
        // Sin título propio: no va a la card (no diría de qué trata).
        {
          'title': 'CNBC',
          'url': 'https://www.cnbc.com/2026/11/12/x.html',
          'source': 'CNBC',
        },
        {
          'title': 'Nvidia names Colette Kress interim CEO',
          'url': 'https://www.bloomberg.com/news/articles/2026-11-12/kress',
          'source': 'Bloomberg',
        },
      ],
    },
  },
);

void main() {
  test('headlines first; without them, the web-search notes with a real '
      'title', () {
    final withHeadlines = NewsCardItems.of({
      'news': [
        {
          'title': 'Nvidia CEO resigns',
          'url': 'https://www.reuters.com/a-1',
          'source': 'Reuters',
          'ticker': 'nvda',
          'published_at': '2026-11-12T10:00:00Z',
        },
      ],
      'context': _noHeadlines.result['context'],
    });
    expect(withHeadlines.map((n) => n.headline), ['Nvidia CEO resigns']);
    expect(withHeadlines.single.ticker, 'NVDA');

    final fromSearch = NewsCardItems.of(
      _noHeadlines.result,
      tickers: const ['NVDA'],
    );
    expect(fromSearch.map((n) => n.headline), [
      'Nvidia ceo jensen huang resigns',
      'Nvidia names Colette Kress interim CEO',
    ]);
    expect(fromSearch.every((n) => n.ticker == 'NVDA'), isTrue);

    expect(
      NewsCardItems.of({
        'news': [],
        'context': {'status': 'failed'},
      }),
      isEmpty,
    );
  });

  test('a text-only news answer without headlines gets the news card from '
      'the web-search notes', () {
    final raw = jsonEncode({
      'version': 'v0.9',
      'updateComponents': {
        'surfaceId': 's',
        'components': [
          {
            'id': 'root',
            'component': 'Column',
            'children': ['a'],
          },
          {
            'id': 'a',
            'component': 'QaAnswerText',
            'text': 'Jensen Huang renunció como CEO de NVIDIA.',
          },
        ],
      },
    });
    final out = AssistantAnswerReview.postProcess(
      raw,
      TurnEvidence(
        calls: const [_noHeadlines],
        turnCalls: const [_noHeadlines],
      ),
    );
    final components =
        ((jsonDecode(out) as Map)['updateComponents'] as Map)['components']
            as List;
    final card = components.cast<Map>().firstWhere(
      (c) => c['component'] == 'QaNewsSummary',
    );
    expect(card['ticker'], 'NVDA');
    expect((card['items'] as List).map((i) => (i as Map)['headline']), [
      'Nvidia ceo jensen huang resigns',
      'Nvidia names Colette Kress interim CEO',
    ]);
  });

  test('"Fuentes" skips only what the news card on screen shows', () {
    const sources = [
      MessageSource(url: 'https://www.cnbc.com/a', source: 'CNBC'),
      MessageSource(url: 'https://www.cnbc.com/b', source: 'CNBC'),
    ];
    SurfaceDefinition surface(String type) => SurfaceDefinition(
      surfaceId: 's',
      components: {
        'n': Component(
          id: 'n',
          type: type,
          properties: {
            'items': [
              {'headline': 'A', 'url': 'https://www.cnbc.com/a'},
            ],
          },
        ),
      },
    );
    expect(
      AnswerSources.notShownIn(
        sources,
        surface('QaNewsSummary'),
      ).map((s) => s.url),
      ['https://www.cnbc.com/b'],
    );
    // Sin la card en pantalla, las citas siguen todas (se tienen que ver).
    expect(AnswerSources.notShownIn(sources, surface('QaInfoList')), sources);
    expect(AnswerSources.notShownIn(sources, null), sources);
  });
}
