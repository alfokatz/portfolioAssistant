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

  test('goal overview keeps the card + its projection strip, nothing more', () {
    final out = AssistantLayoutGuard.enforce(
      _update([
        ('a', 'QaAnswerText'),
        ('g', 'QaGoalCard'),
        ('p', 'QaProjectionStrip'),
        ('m', 'QaMilestoneList'),
        ('p2', 'QaProjectionStrip'),
        ('t', 'QaTipBanner'),
      ]),
    );
    expect(_rootTypes(out), [
      'QaAnswerText',
      'QaGoalCard',
      'QaProjectionStrip',
      'QaTipBanner',
    ]);
  });

  test('a strip that leads keeps the other projection widgets out', () {
    final out = AssistantLayoutGuard.enforce(
      _update([
        ('a', 'QaAnswerText'),
        ('p', 'QaProjectionStrip'),
        ('m', 'QaMilestoneList'),
      ]),
    );
    expect(_rootTypes(out), ['QaAnswerText', 'QaProjectionStrip']);
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

  test('leaves createSurface lines and unknown shapes untouched', () {
    const create =
        '{"version":"v0.9","createSurface":{"surfaceId":"s","catalogId":"x"}}';
    expect(AssistantLayoutGuard.enforce(create), create);
    expect(AssistantLayoutGuard.enforce('not json'), 'not json');
  });
}
