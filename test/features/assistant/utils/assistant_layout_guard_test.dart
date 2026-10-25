import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_layout_guard.dart';

String _update(List<(String id, String type)> children) => jsonEncode({
  'version': 'v0.9',
  'updateComponents': {
    'surfaceId': 's',
    'components': [
      {
        'id': 'root',
        'component': 'Column',
        'children': [for (final (id, _) in children) id],
      },
      for (final (id, type) in children) {'id': id, 'component': type},
    ],
  },
});

List<String> _rootTypes(String normalized) {
  final update =
      (jsonDecode(normalized.split('\n').last) as Map)['updateComponents']
          as Map;
  final components = (update['components'] as List).cast<Map>();
  final byId = {for (final c in components) c['id']: c['component']};
  final root = components.firstWhere((c) => c['id'] == 'root');
  return [for (final id in root['children'] as List) byId[id] as String];
}

void main() {
  test('keeps one data widget: a comparison never gets a chart per ticker', () {
    final out = AssistantLayoutGuard.enforce(
      _update([
        ('a', 'QaAnswerText'),
        ('m', 'QaMetricStrip'),
        ('c1', 'QaPriceChart'),
        ('c2', 'QaPriceChart'),
        ('t', 'QaTipBanner'),
      ]),
    );
    expect(_rootTypes(out), ['QaAnswerText', 'QaMetricStrip', 'QaTipBanner']);
    expect(out, isNot(contains('"c1"')));
  });

  test('a savings plan is the only data widget of a goal answer', () {
    final out = AssistantLayoutGuard.enforce(
      _update([
        ('a', 'QaAnswerText'),
        ('s', 'QaSavingsPlan'),
        ('s2', 'QaSavingsPlan'),
        ('c', 'QaPriceChart'),
        ('t', 'QaTipBanner'),
      ]),
    );
    expect(_rootTypes(out), ['QaAnswerText', 'QaSavingsPlan', 'QaTipBanner']);
  });

  test('one action card per operation, up to 4, nothing else', () {
    final out = AssistantLayoutGuard.enforce(
      _update([
        ('a', 'QaAnswerText'),
        ('p1', 'QaActionProposal'),
        ('p2', 'QaActionProposal'),
        ('c', 'QaPriceChart'),
        ('p3', 'QaActionProposal'),
        ('p4', 'QaActionProposal'),
        ('p5', 'QaActionProposal'),
      ]),
    );
    expect(_rootTypes(out), [
      'QaAnswerText',
      ...List.filled(4, 'QaActionProposal'),
    ]);
    expect(out, isNot(contains('"p5"')));
  });

  test('invest ideas keep up to 3 option cards, never mixed kinds', () {
    final out = AssistantLayoutGuard.enforce(
      _update([
        ('a', 'QaAnswerText'),
        ('o1', 'QaInvestOption'),
        ('o2', 'QaInvestOption'),
        ('b', 'QaBudgetSplit'),
        ('o3', 'QaInvestOption'),
        ('o4', 'QaInvestOption'),
        ('t', 'QaTipBanner'),
      ]),
    );
    expect(_rootTypes(out), [
      'QaAnswerText',
      'QaInvestOption',
      'QaInvestOption',
      'QaInvestOption',
      'QaTipBanner',
    ]);
  });

  test('a "why" answer may add news after a price widget', () {
    final ok = _update([
      ('a', 'QaAnswerText'),
      ('c', 'QaPriceChart'),
      ('n', 'QaNewsSummary'),
      ('t', 'QaTipBanner'),
    ]);
    expect(AssistantLayoutGuard.enforce(ok), ok);

    final notAfterPrice = AssistantLayoutGuard.enforce(
      _update([
        ('a', 'QaAnswerText'),
        ('f', 'QaFundamentals'),
        ('n', 'QaNewsSummary'),
      ]),
    );
    expect(_rootTypes(notAfterPrice), ['QaAnswerText', 'QaFundamentals']);
  });

  test('drops children the model listed but never defined', () {
    final line = jsonEncode({
      'version': 'v0.9',
      'updateComponents': {
        'surfaceId': 's',
        'components': [
          {
            'id': 'root',
            'component': 'Column',
            'children': ['a', 'ghost', 'f'],
          },
          {'id': 'a', 'component': 'QaAnswerText'},
          {'id': 'f', 'component': 'QaFundamentals'},
        ],
      },
    });
    final out = AssistantLayoutGuard.enforce(line);
    expect(_rootTypes(out), ['QaAnswerText', 'QaFundamentals']);
    expect(out, isNot(contains('ghost')));
  });

  test('leaves createSurface lines and unknown shapes untouched', () {
    const create =
        '{"version":"v0.9","createSurface":{"surfaceId":"s","catalogId":"x"}}';
    expect(AssistantLayoutGuard.enforce(create), create);
    expect(AssistantLayoutGuard.enforce('not json'), 'not json');
  });
}
