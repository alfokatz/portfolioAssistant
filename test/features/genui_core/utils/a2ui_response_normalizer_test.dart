import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/genui_core/utils/a2ui_response_normalizer.dart';

void main() {
  test('a component without id gets one instead of breaking the turn', () {
    const raw =
        '{"version":"v0.9","updateComponents":{"surfaceId":"s1","components":['
        '{"component":"QaAnswerText","text":"Hola"},'
        '{"id":"p","component":"QaActionProposal","proposalId":"x"}]}}';
    final out = A2uiResponseNormalizer.normalize(raw, surfaceId: 's1');
    final update =
        LineSplitter.split(out)
            .map((l) => jsonDecode(l) as Map<String, dynamic>)
            .firstWhere((m) => m.containsKey('updateComponents'));
    final components =
        (update['updateComponents'] as Map)['components'] as List;
    final root = components.firstWhere((c) => c['id'] == 'root') as Map;
    expect(root['children'], ['child_0', 'p']);
    expect(components.every((c) => c['id'] is String), isTrue);
  });
}
