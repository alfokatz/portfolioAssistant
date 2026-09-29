import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

/// Tool de prueba: devuelve [result] (o lanza si [fails]) y registra args.
class _EchoTool implements DataTool {
  _EchoTool(
    this.name, {
    this.result = const {'status': 'ok'},
    this.fails = false,
  });

  @override
  final String name;
  final Map<String, Object?> result;
  final bool fails;
  final calls = <Map<String, Object?>>[];

  @override
  String get description => 'test tool $name';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'tickers': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    calls.add(args);
    if (fails) throw StateError('source down');
    return result;
  }
}

/// OpenAI falso: responde [script] en orden y guarda cada body enviado.
class _FakeOpenAi {
  _FakeOpenAi(this.script);

  final List<Map<String, Object?> Function(Map<String, dynamic> body)> script;
  final requests = <Map<String, dynamic>>[];

  late final http.Client client = MockClient((req) async {
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    requests.add(body);
    final i = requests.length - 1;
    if (i >= script.length) {
      return http.Response(
        jsonEncode({
          'error': {'message': 'unexpected request #$i'},
        }),
        500,
      );
    }
    return http.Response(
      jsonEncode({
        'id': 'c$i',
        'object': 'chat.completion',
        'created': 1,
        'model': 'gpt-4.1-mini',
        'system_fingerprint': 'fp',
        'choices': [
          {'index': 0, 'message': script[i](body), 'finish_reason': 'stop'},
        ],
        'usage': {
          'prompt_tokens': 1,
          'completion_tokens': 1,
          'total_tokens': 2,
        },
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  List<String> roles(int i) => [
    for (final m in (requests[i]['messages'] as List).cast<Map>())
      m['role'] as String,
  ];

  List<Map> messages(int i) => (requests[i]['messages'] as List).cast<Map>();
}

Map<String, Object?> _calls(List<(String, String)> idAndName) => {
  'role': 'assistant',
  'content': null,
  'tool_calls': [
    for (final (id, name) in idAndName)
      {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': '{"tickers":["AAPL"]}'},
      },
  ],
};

Map<String, Object?> _answer(String surfaceId, [String text = 'ok']) => {
  'role': 'assistant',
  'content':
      '{"version":"v0.9","createSurface":{"surfaceId":"$surfaceId",'
      '"catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}\n'
      '{"version":"v0.9","updateComponents":{"surfaceId":"$surfaceId",'
      '"components":[{"id":"root","component":"Column","children":["t"]},'
      '{"id":"t","component":"Text","text":"$text"}]}}',
};

String _text(Map message) {
  final content = message['content'];
  if (content is String) return content;
  return (content as List).map((c) => (c as Map)['text'] ?? '').join();
}

void main() {
  OpenAIGenUiService build(
    _FakeOpenAi api, {
    String apiKey = 'sk-test',
    AnswerCheck? answerCheck,
  }) {
    final service = OpenAIGenUiService(
      apiKey: apiKey,
      answerCheck: answerCheck,
      model: 'gpt-4.1-mini',
      systemPrompt: 'SYSTEM',
      catalog: BasicCatalogItems.asCatalog(),
      httpClient: api.client,
    );
    addTearDown(service.dispose);
    return service;
  }

  test(
    'a turn without tool calls is one request and renders the answer',
    () async {
      final api = _FakeOpenAi([(_) => _answer('s0', 'hola')]);
      final service = build(api);

      final outcome = await service.runTurn(
        userText: '¿cómo está mi cartera?',
        surfaceId: 's0',
        tools: [_EchoTool('get_quote')],
        context: 'BRIEF',
      );

      expect(api.requests, hasLength(1));
      expect(api.roles(0), ['system', 'user']);
      expect(_text(api.messages(0)[1]), 'BRIEF\n\n¿cómo está mi cartera?');
      expect(api.requests[0]['tool_choice'], 'auto');
      expect(api.requests[0]['store'], false);
      expect(api.requests[0]['parallel_tool_calls'], true);
      expect(outcome.toolCalls, isEmpty);
      expect(service.controller.registry.getSurface('s0'), isNotNull);
    },
  );

  test('parallel tool calls are answered in order, one failing does not '
      'abort the turn', () async {
    final quote = _EchoTool('get_quote', result: {'status': 'ok', 'p': 1});
    final news = _EchoTool('get_news', fails: true);
    final api = _FakeOpenAi([
      (_) => _calls([('call_q', 'get_quote'), ('call_n', 'get_news')]),
      (_) => _answer('s0'),
    ]);
    final service = build(api);

    final outcome = await service.runTurn(
      userText: '¿por qué bajó AAPL?',
      surfaceId: 's0',
      tools: [quote, news],
    );

    expect(quote.calls, [
      {
        'tickers': ['AAPL'],
      },
    ]);
    expect(api.roles(1), ['system', 'user', 'assistant', 'tool', 'tool']);
    final second = api.messages(1);
    expect(second[3]['tool_call_id'], 'call_q');
    expect(second[4]['tool_call_id'], 'call_n');
    expect(jsonDecode(_text(second[4]))['status'], 'failed');
    expect(outcome.toolCalls.map((c) => c.status), ['ok', 'failed']);
    // Las rondas de continuación no vuelven a pasar por el throttle global
    // ni cambian la lista de tools (prefijo estable para el cache).
    expect(api.requests[1]['tools'], api.requests[0]['tools']);
  });

  test(
    'a model that keeps asking for tools is cut after maxToolRounds',
    () async {
      final api = _FakeOpenAi([
        (_) => _calls([('c1', 'get_quote')]),
        (_) => _calls([('c2', 'get_quote')]),
        (_) => _answer('s0'),
      ]);
      final service = build(api);

      await service.runTurn(
        userText: 'x',
        surfaceId: 's0',
        tools: [_EchoTool('get_quote')],
      );

      expect(api.requests, hasLength(OpenAIGenUiService.maxToolRounds + 1));
      expect(api.requests.last['tool_choice'], 'none');
    },
  );

  test('unknown tools, bad arguments and the per-turn budget become results, '
      'never exceptions', () async {
    final api = _FakeOpenAi([
      (_) => {
        'role': 'assistant',
        'content': null,
        'tool_calls': [
          {
            'id': 'u',
            'type': 'function',
            'function': {'name': 'nope', 'arguments': '{}'},
          },
          {
            'id': 'b',
            'type': 'function',
            'function': {'name': 'get_quote', 'arguments': '{not json'},
          },
          for (var i = 0; i < 6; i++)
            {
              'id': 'k$i',
              'type': 'function',
              'function': {
                'name': 'get_quote',
                'arguments': '{"tickers":["T$i"]}',
              },
            },
        ],
      },
      (_) => _answer('s0'),
    ]);
    final service = build(api);

    final outcome = await service.runTurn(
      userText: 'x',
      surfaceId: 's0',
      tools: [_EchoTool('get_quote')],
    );

    final reasons = outcome.toolCalls.map((c) => c.result['reason']).toList();
    expect(reasons.first, 'unknown_tool');
    expect(reasons[1], 'invalid_arguments');
    expect(reasons.where((r) => r == 'budget_exhausted'), hasLength(2));
    // 8 tool_calls → 8 tool messages, aunque varias no se ejecutaron.
    expect(api.roles(1).where((r) => r == 'tool'), hasLength(8));
  });

  test('abortCheck cuts the turn after the first round and drops it from '
      'memory', () async {
    final api = _FakeOpenAi([
      (_) => _calls([('c1', 'get_quote')]),
      (_) => _answer('s1'),
    ]);
    final service = build(api);

    await expectLater(
      service.runTurn(
        userText: 'AMZN',
        surfaceId: 's0',
        tools: [
          _EchoTool('get_quote', result: {'status': 'locked'}),
        ],
        abortCheck:
            (round) => round.first.status == 'locked' ? 'paywall' : null,
      ),
      throwsA(
        isA<TurnAbortedException>().having(
          (e) => e.reason,
          'reason',
          'paywall',
        ),
      ),
    );
    expect(api.requests, hasLength(1));
    expect(service.log.turns, isEmpty);

    await service.runTurn(userText: 'hola', surfaceId: 's1', tools: const []);
    expect(api.roles(1), ['system', 'user']);
  });

  test('follow-ups see earlier tool results; the ephemeral context is only '
      'sent on its own turn', () async {
    final api = _FakeOpenAi([
      (_) => _calls([('c1', 'get_quote')]),
      (_) => _answer('s0'),
      (_) => _answer('s1'),
    ]);
    final service = build(api);
    final quote = _EchoTool('get_quote', result: {'status': 'ok', 'day': 1.2});

    await service.runTurn(
      userText: '¿A cuánto está AAPL?',
      surfaceId: 's0',
      tools: [quote],
      context: 'BRIEF-1',
    );
    await service.runTurn(
      userText: '¿cuánto subió?',
      surfaceId: 's1',
      tools: [quote],
      context: 'BRIEF-2',
    );

    expect(api.roles(2), [
      'system',
      'user', // ¿A cuánto está AAPL? (sin BRIEF-1)
      'assistant', // tool_calls
      'tool',
      'assistant', // A2UI final del turno 1
      'user', // BRIEF-2 + ¿cuánto subió?
    ]);
    final third = api.messages(2);
    expect(_text(third[1]), '¿A cuánto está AAPL?');
    expect(_text(third[3]), contains('"day":1.2'));
    expect(_text(third[5]), startsWith('BRIEF-2'));
  });

  test('a genui validation error triggers one repair round without tools, '
      'at most once per turn', () async {
    final api = _FakeOpenAi([
      (_) => _answer('s0'),
      (_) => _answer('s0', 'reparado'),
    ]);
    final service = build(api);
    await service.runTurn(
      userText: 'x',
      surfaceId: 's0',
      tools: [_EchoTool('get_quote')],
    );

    ChatMessage validationError() => ChatMessage.user(
      '',
      parts: [
        UiInteractionPart.create(
          jsonEncode({
            'version': 'v0.9',
            'error': {
              'code': 'VALIDATION_FAILED',
              'surfaceId': 's0',
              'message': 'Widget with id: investOptionNVDA not found.',
            },
          }),
        ),
      ],
    );

    await service.handleSend(validationError());
    await service.handleSend(validationError()); // tope: se ignora

    expect(api.requests, hasLength(2));
    expect(api.requests[1]['tool_choice'], 'none');
    final repair = _text(api.messages(1).last);
    expect(repair, contains('ERROR DE VALIDACIÓN'));
    expect(repair, contains('investOptionNVDA'));
    expect(service.log.currentTurn!.finalText, contains('reparado'));
  });

  // Regresión del bug de contexto de BAC: una card vieja que se reconstruye
  // (nuevo mensaje, scroll) y reporta un error de render llegaba al repair
  // del turno ACTUAL, y la reacción del modelo a "ERROR DE VALIDACIÓN"
  // reemplazaba una respuesta correcta.
  test('render errors (no surfaceId) and errors of older surfaces never '
      'repair the current turn', () async {
    final api = _FakeOpenAi([
      (_) => _answer('s0', 'fundamentals'),
      (_) => _answer('s1', 'analisis correcto'),
    ]);
    final service = build(api);
    await service.runTurn(
      userText: 'fundamentals de BAC',
      surfaceId: 's0',
      tools: [_EchoTool('get_fundamentals')],
    );
    await service.runTurn(
      userText: '¿me analizás estos fundamentales?',
      surfaceId: 's1',
      tools: [_EchoTool('get_fundamentals')],
    );

    ChatMessage error(Map<String, Object?> body) => ChatMessage.user(
      '',
      parts: [
        UiInteractionPart.create(jsonEncode({'version': 'v0.9', 'error': body})),
      ],
    );
    // De render: genui no dice de qué surface es.
    await service.handleSend(
      error({
        'code': 'INTERNAL_ERROR',
        'message': 'An unexpected system error occurred.',
      }),
    );
    // De validación, pero de la surface del turno anterior.
    await service.handleSend(
      error({
        'code': 'VALIDATION_FAILED',
        'surfaceId': 's0',
        'message': 'Widget with id: tip not found.',
      }),
    );

    expect(api.requests, hasLength(2), reason: 'ningún pedido de repair');
    expect(service.log.currentTurn!.finalText, contains('analisis correcto'));
  });

  test('a text rewrite that drops the card is discarded: the original stays',
      () async {
    final api = _FakeOpenAi([
      (_) => _answer('s0', 'original con card'),
      (_) => _answer('s0', 'solo texto'),
    ]);
    var checks = 0;
    final service = build(
      api,
      answerCheck: (raw, evidence) {
        checks++;
        return AnswerCorrection(
          'fix the text',
          requiresTools: false,
          rejectRewrite: (rewritten) => rewritten.contains('solo texto'),
        );
      },
    );
    await service.runTurn(
      userText: 'x',
      surfaceId: 's0',
      tools: [_EchoTool('get_quote')],
    );
    expect(checks, 1);
    expect(api.requests, hasLength(2));
    // La reescritura se pidió sin tools.
    expect(api.requests[1]['tool_choice'], 'none');
    expect(service.log.currentTurn!.finalText, contains('original con card'));
  });

  test('without an API key the turn fails before any request', () async {
    final api = _FakeOpenAi([]);
    final service = build(api, apiKey: '');

    await expectLater(
      service.runTurn(userText: 'hola', surfaceId: 's0', tools: const []),
      throwsA(isA<StateError>()),
    );
    expect(api.requests, isEmpty);
  });

  test(
    'two turns sent without awaiting are serialized, never interleaved',
    () async {
      final api = _FakeOpenAi([
        (_) => _answer('s0', 'uno'),
        (_) => _answer('s1', 'dos'),
      ]);
      final service = build(api);

      final first = service.runTurn(
        userText: 'primero',
        surfaceId: 's0',
        tools: const [],
      );
      final second = service.runTurn(
        userText: 'segundo',
        surfaceId: 's1',
        tools: const [],
      );
      await Future.wait([first, second]);

      expect(api.roles(1), ['system', 'user', 'assistant', 'user']);
      expect(_text(api.messages(1)[1]), 'primero');
      expect(_text(api.messages(1)[3]), 'segundo');
    },
  );

  test('a needs_retry result forces the next round to call that tool again, '
      'once', () async {
    final api = _FakeOpenAi([
      (_) => _calls([('c1', 'get_quote')]),
      (_) => _calls([('c2', 'get_quote')]),
      (_) => _answer('s0'),
    ]);
    final service = build(api);
    var runs = 0;
    final tool = _RetryOnceTool(() => runs++);

    await service.runTurn(userText: 'x', surfaceId: 's0', tools: [tool]);

    expect(api.requests[1]['tool_choice'], {
      'type': 'function',
      'function': {'name': 'get_quote'},
    });
    expect(api.requests[2]['tool_choice'], 'none');
    expect(runs, 2);
  });

  test('an answer rejected by answerCheck gets one extra round with tools '
      'required, and the rejected answer is not kept in memory', () async {
    final api = _FakeOpenAi([
      (_) => _answer('s0', 'inventado'),
      (_) => _calls([('c1', 'get_quote')]),
      (_) => _answer('s0', 'con datos'),
    ]);
    var checks = 0;
    final service = build(
      api,
      answerCheck: (raw, evidence) {
        final calls = evidence.calls;
        checks++;
        return calls.isEmpty
            ? const AnswerCorrection('call get_quote first')
            : null;
      },
    );

    final outcome = await service.runTurn(
      userText: 'x',
      surfaceId: 's0',
      tools: [_EchoTool('get_quote')],
    );

    expect(checks, 1);
    expect(api.requests[1]['tool_choice'], 'required');
    expect(api.roles(1), ['system', 'user', 'assistant', 'user']);
    expect(_text(api.messages(1).last), 'call get_quote first');
    expect(outcome.toolCalls, hasLength(1));
    expect(service.log.currentTurn!.finalText, contains('con datos'));
    expect(service.log.render().map((m) => m.role.name), [
      'system',
      'user',
      'assistant',
      'tool',
      'assistant',
    ]);
  });
}

class _RetryOnceTool extends _EchoTool {
  _RetryOnceTool(this.onRun) : super('get_quote');

  final void Function() onRun;
  var _first = true;

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    onRun();
    if (_first) {
      _first = false;
      return {'status': DataTool.needsRetryStatus};
    }
    return {'status': 'ok'};
  }
}
