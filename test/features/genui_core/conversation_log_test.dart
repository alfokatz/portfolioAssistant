import 'dart:math';

import 'package:dart_openai/dart_openai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/conversation_log.dart';

OpenAIChatCompletionChoiceMessageModel _call(List<String> ids) =>
    OpenAIChatCompletionChoiceMessageModel.fromMap({
      'role': 'assistant',
      'content': null,
      'tool_calls': [
        for (final id in ids)
          {
            'id': id,
            'type': 'function',
            'function': {'name': 'get_quote', 'arguments': '{}'},
          },
      ],
    });

ToolExchange _exchange(List<String> ids) => ToolExchange(
  call: _call(ids),
  results: [
    for (final id in ids)
      RequestFunctionMessage(
        role: OpenAIChatMessageRole.tool,
        content: [OpenAIChatCompletionChoiceMessageContentItemModel.text('{}')],
        toolCallId: id,
      ),
  ],
);

/// Las dos reglas que la API hace cumplir con un 400.
void _expectValidPairing(List<OpenAIChatCompletionChoiceMessageModel> msgs) {
  for (var i = 0; i < msgs.length; i++) {
    final m = msgs[i];
    if (m.role == OpenAIChatMessageRole.assistant && m.haveToolCalls) {
      final ids = m.toolCalls!.map((c) => c.id).toList();
      final replies = [
        for (var j = i + 1; j <= i + ids.length && j < msgs.length; j++)
          msgs[j],
      ];
      expect(
        replies.map((r) => r.role),
        everyElement(OpenAIChatMessageRole.tool),
      );
      expect(replies.map((r) => (r as RequestFunctionMessage).toolCallId), ids);
    }
    if (m.role == OpenAIChatMessageRole.tool) {
      var k = i - 1;
      while (msgs[k].role == OpenAIChatMessageRole.tool) {
        k--;
      }
      expect(msgs[k].haveToolCalls, isTrue);
    }
  }
}

String _text(OpenAIChatCompletionChoiceMessageModel m) =>
    m.content?.map((c) => c.text ?? '').join() ?? '';

void main() {
  test('never emits a tool_calls message without its tool replies, or a '
      'tool reply without its call (randomized histories)', () {
    final random = Random(7);
    for (var run = 0; run < 200; run++) {
      final log = ConversationLog(
        systemPrompt: 'S',
        rawTurns: 1 + random.nextInt(3),
        maxTurns: 2 + random.nextInt(6),
      );
      final turns = 1 + random.nextInt(10);
      for (var t = 0; t < turns; t++) {
        final turn = log.beginTurn('q$t', context: 'ctx$t');
        for (var r = 0; r < random.nextInt(3); r++) {
          turn.exchanges.add(
            _exchange([
              for (var k = 0; k <= random.nextInt(3); k++) 'c${t}_${r}_$k',
            ]),
          );
        }
        // Algunos turnos fallan (sin respuesta final).
        if (random.nextInt(4) != 0) turn.finalText = 'a$t';
      }
      final rendered = log.render();
      expect(rendered.first.role, OpenAIChatMessageRole.system);
      _expectValidPairing(rendered);
    }
  });

  test('old turns are compacted to question + answer; recent ones keep their '
      'tool traffic', () {
    final log = ConversationLog(systemPrompt: 'S', rawTurns: 1);
    final first =
        log.beginTurn('¿A cuánto está AAPL?')
          ..exchanges.add(_exchange(['c1']))
          ..finalText = 'A2UI-1';
    expect(first.exchanges, hasLength(1));
    log.beginTurn('¿cuánto subió?')
      ..exchanges.add(_exchange(['c2']))
      ..finalText = 'A2UI-2';

    final roles = log.render().map((m) => m.role.name).toList();
    expect(roles, [
      'system',
      'user', 'assistant', // turno 1 compactado
      'user', 'assistant', 'tool', 'assistant', // turno 2 crudo
    ]);
  });

  test('the ephemeral context only goes with the current turn', () {
    final log = ConversationLog(systemPrompt: 'S');
    log.beginTurn('uno', context: 'BRIEF-1').finalText = 'r1';
    log.beginTurn('dos', context: 'BRIEF-2');
    final users = [
      for (final m in log.render())
        if (m.role == OpenAIChatMessageRole.user) _text(m),
    ];
    expect(users, ['uno', 'BRIEF-2\n\ndos']);
  });

  test('keeps at most maxTurns turns', () {
    final log = ConversationLog(systemPrompt: 'S', maxTurns: 3);
    for (var i = 0; i < 5; i++) {
      log.beginTurn('q$i').finalText = 'a$i';
    }
    expect(log.turns.map((t) => t.userText), ['q2', 'q3', 'q4']);
  });

  test('turns resolved outside the loop are remembered as plain text', () {
    final log = ConversationLog(systemPrompt: 'S')
      ..addCompletedTurn('Tengo 500', 'Mostré 4 candidatos');
    expect(log.render().map((m) => m.role.name), [
      'system',
      'user',
      'assistant',
    ]);
  });

  test('the pinned context goes right after the system prompt and is '
      'replaced, not accumulated', () {
    final log = ConversationLog(systemPrompt: 'S')..pinnedContext = 'BRIEF-1';
    log.beginTurn('uno').finalText = 'r1';
    log.pinnedContext = 'BRIEF-2';
    log.beginTurn('dos');
    final rendered = log.render();
    expect(rendered.map((m) => m.role.name), [
      'system',
      'system',
      'user',
      'assistant',
      'user',
    ]);
    expect(_text(rendered[1]), 'BRIEF-2');
  });
}
