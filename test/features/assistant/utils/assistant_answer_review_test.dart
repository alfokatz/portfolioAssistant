import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
import 'package:portfolio_assistant/features/assistant/tools/advice_tools.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_answer_review.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

const _fundamentals = ToolCallRecord(
  name: 'get_fundamentals',
  args: {
    'tickers': ['BAC'],
  },
  result: {
    'status': 'ok',
    'fundamentals': {
      'BAC': {'pe_ttm': 11.63, 'net_margin_ttm': 30.16, 'roe_ttm': 11.13},
    },
  },
);

ToolCallRecord _other(String name) => ToolCallRecord(
  name: name,
  args: const {
    'tickers': ['BAC'],
  },
  result: const {'status': 'empty'},
);

final _evidence = TurnEvidence(
  calls: [
    _fundamentals,
    _other('get_quote'),
    _other('get_earnings'),
    _other('get_news'),
  ],
);

String _answer(List<Map<String, Object?>> children) => jsonEncode({
  'version': 'v0.9',
  'updateComponents': {
    'surfaceId': 's',
    'components': [
      {
        'id': 'root',
        'component': 'Column',
        'children': [for (final c in children) c['id']],
      },
      ...children,
    ],
  },
});

Map<String, Object?> _intro(String text) => {
  'id': 'a',
  'component': 'QaAnswerText',
  'text': text,
};

Map<String, Object?> _analysis(String summary) => {
  'id': 'x',
  'component': 'QaCompanyAnalysis',
  'ticker': 'BAC',
  'summary': summary,
};

void main() {
  group('phantom action', () {
    String answer(String text) =>
        '{"version":"v0.9","updateComponents":{"surfaceId":"s","components":'
        '[{"id":"root","component":"Column","children":["a"]},'
        '{"id":"a","component":"QaAnswerText","text":"$text"}]}}';
    const claim =
        'Preparé la operación de compra de 10 acciones de Apple, revisala y '
        'confirmala.';

    test('claiming a prepared operation without propose_* is rejected', () {
      final correction = AssistantAnswerReview.check(
        answer(claim),
        const TurnEvidence(calls: []),
      );
      expect(correction, isNotNull);
      expect(correction!.requiresTools, isTrue);
      expect(correction.message, contains('propose_buy'));
    });

    test('with a propose_* call this turn it passes', () {
      const call = ToolCallRecord(
        name: 'propose_buy',
        args: {},
        result: {'status': 'ok', 'proposal_id': 'p1'},
      );
      expect(
        AssistantAnswerReview.check(
          answer(claim),
          const TurnEvidence(calls: [call], turnCalls: [call]),
        ),
        isNull,
      );
    });

    test('asking for what is missing is fine', () {
      expect(
        AssistantAnswerReview.check(
          answer('¿Cuántas acciones compraste y en qué fecha?'),
          const TurnEvidence(calls: []),
        ),
        isNull,
      );
    });
  });

  test('a clean analysis passes', () {
    final raw = _answer([
      _intro('Este es el análisis de BAC.'),
      _analysis(
        'Es un banco grande que gana 30 de cada 100 dólares que vende.',
      ),
    ]);
    expect(AssistantAnswerReview.check(raw, _evidence), isNull);
  });

  test('an unbacked number asks to rewrite the text, without tools', () {
    final raw = _answer([
      _intro('Este es el análisis de BAC.'),
      _analysis('Su P/E está 40% por debajo del sector.'),
    ]);
    final correction = AssistantAnswerReview.check(raw, _evidence);
    expect(correction, isNotNull);
    expect(correction!.requiresTools, isFalse);
    expect(correction.message, contains('40'));
  });

  test('buy/sell advice asks to rewrite the text', () {
    final raw = _answer([
      _intro('Este es el análisis de BAC.'),
      _analysis('Es buen momento para comprar.'),
    ]);
    expect(
      AssistantAnswerReview.check(raw, _evidence)?.message,
      contains('advice'),
    );
  });

  test('an analysis missing a source asks to call it (with tools)', () {
    final raw = _answer([_intro('Análisis de BAC.'), _analysis('Un banco.')]);
    final correction = AssistantAnswerReview.check(
      raw,
      const TurnEvidence(calls: [_fundamentals]),
    );
    expect(correction?.requiresTools, isTrue);
    expect(correction?.message, contains('get_news'));
  });

  test('an analysis without any tool result for the ticker needs tools', () {
    final raw = _answer([_intro('Análisis de BAC.'), _analysis('Un banco.')]);
    final correction = AssistantAnswerReview.check(raw, TurnEvidence.empty);
    expect(correction?.requiresTools, isTrue);
  });

  test('an intro that lists the card numbers costs no extra round', () {
    final raw = _answer([
      _intro('Aquí tienes: P/E 11,63x, margen neto 30,16% y ROE 11,13%.'),
      {
        'id': 'f',
        'component': 'QaFundamentals',
        'ticker': 'BAC',
        'items': [
          {'label': 'P/E', 'value': '11,63x'},
          {'label': 'Margen neto', 'value': '30,16%'},
        ],
      },
    ]);
    expect(AssistantAnswerReview.check(raw, _evidence), isNull);
    final out = AssistantAnswerReview.postProcess(raw, _evidence);
    expect(
      out,
      contains(
        'Estos son los indicadores de BAC que tienen que ver con tu pregunta.',
      ),
    );
    expect(out, isNot(contains('Aquí tienes')));
  });

  test('an intro that names the period but not the card numbers is kept', () {
    final raw = _answer([
      _intro(
        'Comparé cómo se movieron tus posiciones en los últimos 30 días: a '
        'la izquierda la que más subió, a la derecha la que más bajó.',
      ),
      {
        'id': 'm',
        'component': 'QaTopMovers',
        'periodLabel': 'últimos 30 días',
        'items': [
          {'ticker': 'VOO', 'changePct': -0.3},
          {'ticker': 'AMZN', 'changePct': -5.0},
        ],
      },
    ]);
    final out = AssistantAnswerReview.postProcess(raw, _evidence);
    expect(out, contains('Comparé cómo se movieron tus posiciones'));
  });

  test('an intro made only of card numbers falls back to describing the '
      'card, never to a content-free opener', () {
    final raw = _answer([
      _intro('VOO bajó 0,3% y AMZN bajó 5,0%.'),
      {
        'id': 'm',
        'component': 'QaTopMovers',
        'periodLabel': 'últimos 30 días',
        'items': [
          {'ticker': 'VOO', 'changePct': -0.3},
          {'ticker': 'AMZN', 'changePct': -5.0},
        ],
      },
    ]);
    final out = AssistantAnswerReview.postProcess(raw, _evidence);
    expect(out, isNot(contains('0,3')));
    expect(out, isNot(contains('Esto es lo que encontré')));
    expect(out, contains('la que mejor le fue'));
  });

  test('postProcess drops what the model did not fix', () {
    final normalized = _answer([
      _intro('Aquí tienes: P/E 11,63x y margen neto 30,16%.'),
      _analysis('Es un banco grande. Su P/E está 40% por debajo del sector.'),
    ]);
    final out = AssistantAnswerReview.postProcess(normalized, _evidence);
    final components =
        ((jsonDecode(out) as Map)['updateComponents'] as Map)['components']
            as List;
    final byId = <Object?, Map>{
      for (final c in components) (c as Map)['id']: c,
    };
    expect(byId['x']!['summary'], 'Es un banco grande.');
    expect(byId['a']!['text'], 'Este es el análisis de BAC.');
  });

  test('postProcess adds the intro sentence when the model dropped it', () {
    final out = AssistantAnswerReview.postProcess(
      _answer([_analysis('Es un banco grande.')]),
      _evidence,
    );
    final update = (jsonDecode(out) as Map)['updateComponents'] as Map;
    final root = (update['components'] as List).cast<Map>().firstWhere(
      (c) => c['id'] == 'root',
    );
    expect((root['children'] as List).first, 'analysisIntro');
    expect(out, contains('Este es el análisis de BAC.'));
  });

  test('a text-only answer to a locked Gold source gets the Gold teaser '
      'right after the intro', () {
    const locked = ToolCallRecord(
      name: 'get_news',
      args: {
        'tickers': ['NVDA'],
      },
      result: {'status': 'locked', 'required_plan': 'gold'},
    );
    final out = AssistantAnswerReview.postProcess(
      _answer([_intro('Las noticias están incluidas en Gold.')]),
      const TurnEvidence(calls: [locked], turnCalls: [locked]),
    );
    final update = (jsonDecode(out) as Map)['updateComponents'] as Map;
    final components = (update['components'] as List).cast<Map>();
    final root = components.firstWhere((c) => c['id'] == 'root');
    expect(root['children'], ['a', 'goldTeaser']);
    expect(
      components.firstWhere((c) => c['id'] == 'goldTeaser')['ticker'],
      'NVDA',
    );
  });

  test('no teaser when a data card already answers', () {
    const locked = ToolCallRecord(
      name: 'get_news',
      args: {
        'tickers': ['NVDA'],
      },
      result: {'status': 'locked'},
    );
    final out = AssistantAnswerReview.postProcess(
      _answer([
        _intro('NVDA subió.'),
        {'id': 'p', 'component': 'QaPriceChart', 'ticker': 'NVDA'},
      ]),
      const TurnEvidence(calls: [locked], turnCalls: [locked]),
    );
    expect(out, isNot(contains('QaGoldTeaser')));
  });

  group('news card', () {
    const news = ToolCallRecord(
      name: 'get_news',
      args: {
        'tickers': ['AMZN'],
      },
      result: {
        'status': 'ok',
        'as_of': '2026-10-12T17:00:00Z',
        'news': [
          {
            'ticker': 'AMZN',
            'title': 'Amazon in Talks to Acquire Decart AI',
            'url': 'https://www.bloomberg.com/news/amazon-decart',
            'source': 'Bloomberg',
            'snippet': '',
            'published_at': '2026-10-11T15:00:00Z',
          },
          {
            'ticker': 'AMZN',
            'title': 'Amazon Launches Alexa+ Tablet',
            'url': 'https://www.reuters.com/amazon-alexa-tablet',
            'source': 'Reuters',
            'snippet': 'The tablet runs Google apps.',
            'published_at': '2026-10-08T15:00:00Z',
          },
        ],
        'context': {'status': 'ok', 'summary': 'Amazon negocia...'},
      },
    );

    List<Map> componentsOf(String out) =>
        (((jsonDecode(out) as Map)['updateComponents'] as Map)['components']
                as List)
            .cast<Map>();

    test('"¿qué noticias hay de AMZN?" answered with text only gets the '
        'news card with the real headlines, after the text', () {
      final out = AssistantAnswerReview.postProcess(
        _answer([_intro('Estas son las noticias recientes de Amazon.')]),
        const TurnEvidence(calls: [news], turnCalls: [news]),
      );
      final components = componentsOf(out);
      final root = components.firstWhere((c) => c['id'] == 'root');
      expect(root['children'], ['a', 'newsCard']);
      final card = components.firstWhere((c) => c['id'] == 'newsCard');
      expect(card['component'], 'QaNewsSummary');
      expect(card['ticker'], 'AMZN');
      final items = (card['items'] as List).cast<Map>();
      expect(items.map((i) => i['headline']), [
        'Amazon in Talks to Acquire Decart AI',
        'Amazon Launches Alexa+ Tablet',
      ]);
      expect(items.first['url'], 'https://www.bloomberg.com/news/amazon-decart');
      expect(items.first['source'], 'Bloomberg');
      expect(items.first['dateLabel'], 'ayer');
      expect(items.last['summaryLine'], 'The tablet runs Google apps.');
    });

    test('"why did it move": the news card follows the price widget', () {
      final out = AssistantAnswerReview.postProcess(
        _answer([
          _intro('AMZN bajó.'),
          {'id': 'p', 'component': 'QaTickerMove', 'ticker': 'AMZN'},
        ]),
        const TurnEvidence(calls: [news], turnCalls: [news]),
      );
      final root = componentsOf(out).firstWhere((c) => c['id'] == 'root');
      expect(root['children'], ['a', 'p', 'newsCard']);
    });

    test('nothing added when the model already showed them, when another '
        'card answers, or without headlines', () {
      final shown = _answer([
        _intro('Noticias de AMZN.'),
        {'id': 'n', 'component': 'QaNewsSummary', 'ticker': 'AMZN', 'items': []},
      ]);
      expect(
        AssistantAnswerReview.postProcess(
          shown,
          const TurnEvidence(calls: [news], turnCalls: [news]),
        ),
        isNot(contains('newsCard')),
      );
      expect(
        AssistantAnswerReview.postProcess(
          _answer([_intro('Análisis.'), _analysis('Un banco.')]),
          const TurnEvidence(calls: [news], turnCalls: [news]),
        ),
        isNot(contains('newsCard')),
      );
      const empty = ToolCallRecord(
        name: 'get_news',
        args: {},
        result: {'status': 'ok', 'news': [], 'context': {'status': 'ok'}},
      );
      expect(
        AssistantAnswerReview.postProcess(
          _answer([_intro('Amazon negocia una compra.')]),
          const TurnEvidence(calls: [empty], turnCalls: [empty]),
        ),
        isNot(contains('newsCard')),
      );
    });
  });

  group('goal plan card', () {
    final plan = ToolCallRecord(
      name: GetGoalProjectionTool.toolName,
      args: const {},
      result: {
        'status': 'ok',
        ...GoalProjectionBuilder.build(
          currentPortfolioValue: 10000,
          targetAmount: 25000,
          targetDate: DateTime.utc(2029, 10, 11),
          label: 'Auto',
          isPurchase: true,
          asOf: DateTime.utc(2026, 10, 11),
        ),
      },
    );
    final planId = plan.result[GoalProjectionBuilder.planIdKey];

    List<Map> components(String out) =>
        (((jsonDecode(out) as Map)['updateComponents'] as Map)['components']
                as List)
            .cast<Map>();

    test('a complete plan answered with text only gets its card', () {
      final out = AssistantAnswerReview.postProcess(
        _answer([_intro('Te armé el plan para el auto.')]),
        TurnEvidence(calls: [plan], turnCalls: [plan]),
      );
      final all = components(out);
      expect(all.firstWhere((c) => c['id'] == 'root')['children'], [
        'a',
        'planCard',
      ]);
      final card = all.firstWhere((c) => c['id'] == 'planCard');
      expect(card['component'], 'QaSavingsPlan');
      expect(card['planId'], planId);
    });

    test('a card with a wrong planId is pointed at the plan of the turn', () {
      final out = AssistantAnswerReview.postProcess(
        _answer([
          _intro('Te armé el plan para el auto.'),
          {'id': 'p', 'component': 'QaSavingsPlan', 'planId': 'plan_x'},
        ]),
        TurnEvidence(calls: [plan], turnCalls: [plan]),
      );
      final all = components(out);
      expect(all.where((c) => c['component'] == 'QaSavingsPlan'), hasLength(1));
      expect(all.firstWhere((c) => c['id'] == 'p')['planId'], planId);
    });

    group('"¿cómo va mi meta?" (a saved goal, nothing changed)', () {
      final status = ToolCallRecord(
        name: GetGoalProjectionTool.toolName,
        args: const {'goal_id': 'g1'},
        result: plan.result,
      );

      test('the plan card nobody asked for becomes the goal status', () {
        final out = AssistantAnswerReview.postProcess(
          _answer([
            _intro('Tu meta Auto va en camino.'),
            {'id': 'p', 'component': 'QaSavingsPlan', 'planId': planId},
          ]),
          TurnEvidence(calls: [status], turnCalls: [status]),
        );
        final all = components(out);
        expect(all.where((c) => c['component'] == 'QaSavingsPlan'), isEmpty);
        expect(all.firstWhere((c) => c['id'] == 'root')['children'], [
          'a',
          'goalStatus',
        ]);
        final card = all.firstWhere((c) => c['id'] == 'goalStatus');
        expect(card['component'], 'QaGoalStatus');
        expect(card['goal'], 'Auto');
      });

      test('a text-only answer gets the goal status, not the plan', () {
        final out = AssistantAnswerReview.postProcess(
          _answer([_intro('Tu meta Auto va en camino.')]),
          TurnEvidence(calls: [status], turnCalls: [status]),
        );
        expect(out, isNot(contains('QaSavingsPlan')));
        expect(out, contains('QaGoalStatus'));
      });

      test('asking to change it ("hacelo en 2 años") still shows the new '
          'plan', () {
        final change = ToolCallRecord(
          name: GetGoalProjectionTool.toolName,
          args: const {'goal_id': 'g1', 'target_date': '2028-10-11'},
          result: plan.result,
        );
        final out = AssistantAnswerReview.postProcess(
          _answer([_intro('Así queda en dos años.')]),
          TurnEvidence(calls: [change], turnCalls: [change]),
        );
        expect(out, contains('QaSavingsPlan'));
        expect(out, isNot(contains('QaGoalStatus')));
      });
    });

    test('a plan from an earlier turn is not injected', () {
      final out = AssistantAnswerReview.postProcess(
        _answer([_intro('¿Para cuándo lo necesitás?')]),
        TurnEvidence(calls: [plan]),
      );
      expect(out, isNot(contains('QaSavingsPlan')));
    });
  });
}
