import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
    expect(out, contains('Esto es lo que encontré sobre BAC.'));
    expect(out, isNot(contains('Aquí tienes')));
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
}
