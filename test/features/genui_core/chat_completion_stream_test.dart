import 'dart:convert';

import 'package:dart_openai/dart_openai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/chat_completion_stream.dart';

import '../assistant/fakes/assistant_fakes.dart';

const _sse = {'content-type': 'text/event-stream; charset=utf-8'};

void main() {
  final user = OpenAIChatCompletionChoiceMessageModel(
    role: OpenAIChatMessageRole.user,
    content: [OpenAIChatCompletionChoiceMessageContentItemModel.text('hola')],
  );

  Future<OpenAIChatCompletionChoiceMessageModel> run(
    http.Client client, {
    List<String>? seen,
  }) => ChatCompletionStream.create(
    client: client,
    model: 'gpt-6-luna',
    messages: [user],
    toolChoice: 'auto',
    temperature: 0.35,
    onContent: seen?.add,
  );

  test('text arrives piece by piece and ends as the same message', () async {
    late Map<String, dynamic> sent;
    final client = MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        ScriptedOpenAi.sseOf(textReply('Tu cartera subió en la semana.')),
        200,
        headers: _sse,
      );
    });
    final seen = <String>[];
    final message = await run(client, seen: seen);

    expect(sent['stream'], isTrue);
    expect(sent['model'], 'gpt-6-luna');
    expect(sent['tool_choice'], 'auto');
    expect((sent['messages'] as List).single, user.toMap());
    expect(seen.length, greaterThan(2));
    expect(seen.last, 'Tu cartera subió en la semana.');
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i].startsWith(seen[i - 1]), isTrue);
    }
    expect(message.content!.single.text, 'Tu cartera subió en la semana.');
    expect(message.toolCalls, anyOf(isNull, isEmpty));
  });

  test('tool calls are assembled from their pieces', () async {
    final client = MockClient(
      (_) async => http.Response(
        ScriptedOpenAi.sseOf(
          toolCallsReply([
            (
              'call_1',
              'get_quote',
              {
                'tickers': ['AAPL'],
              },
            ),
            (
              'call_2',
              'get_news',
              {
                'tickers': ['MSFT', 'GOOGL'],
              },
            ),
          ]),
        ),
        200,
        headers: _sse,
      ),
    );
    final seen = <String>[];
    final message = await run(client, seen: seen);

    expect(seen, isEmpty);
    expect(message.content, anyOf(isNull, isEmpty));
    final calls = message.toolCalls!;
    expect(calls.map((c) => c.id), ['call_1', 'call_2']);
    expect(calls.map((c) => c.function.name), ['get_quote', 'get_news']);
    expect(jsonDecode(calls[1].function.arguments), {
      'tickers': ['MSFT', 'GOOGL'],
    });
  });

  test(
    "OpenAI's errors keep their shape (the service retries the 429)",
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'Rate limit reached. Please try again in 2s.'},
          }),
          429,
        ),
      );
      await expectLater(
        run(client),
        throwsA(
          isA<RequestFailedException>()
              .having((e) => e.statusCode, 'status', 429)
              .having((e) => e.message, 'message', contains('try again in 2s')),
        ),
      );
    },
  );
}
