import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

class _Tool implements DataTool {
  @override
  String get name => 'get_quote';
  @override
  String get description => 'quote';
  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {},
    'additionalProperties': false,
  };
  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async => const {
    'status': 'ok',
  };
}

http.Response _completion(Map<String, Object?> message) => http.Response(
  jsonEncode({
    'id': 'c',
    'object': 'chat.completion',
    'created': 1,
    'model': 'gpt-4.1-mini',
    'system_fingerprint': 'fp',
    'choices': [
      {'index': 0, 'message': message, 'finish_reason': 'stop'},
    ],
    'usage': {'prompt_tokens': 1, 'completion_tokens': 1, 'total_tokens': 2},
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _answer(String surfaceId) => {
  'role': 'assistant',
  'content':
      '{"version":"v0.9","createSurface":{"surfaceId":"$surfaceId",'
      '"catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}\n'
      '{"version":"v0.9","updateComponents":{"surfaceId":"$surfaceId",'
      '"components":[{"id":"root","component":"Text","text":"ok"}]}}',
};

const _toolCall = {
  'role': 'assistant',
  'content': null,
  'tool_calls': [
    {
      'id': 'c1',
      'type': 'function',
      'function': {'name': 'get_quote', 'arguments': '{}'},
    },
  ],
};

void main() {
  final endpoint = Uri.parse('https://proj.supabase.co/functions/v1/ai-chat');

  test(
    'every request goes to the proxy with the user JWT, never an OpenAI key, '
    'and all rounds of a turn share one turn id',
    () async {
      final seen = <http.Request>[];
      var n = 0;
      final inner = MockClient((req) async {
        seen.add(req);
        n++;
        return _completion(n == 1 ? _toolCall : _answer(n == 2 ? 's0' : 's1'));
      });
      final service = OpenAIGenUiService(
        proxy: AiProxyConfig.fixed(endpoint, 'user-jwt', anonKey: 'anon'),
        model: 'gpt-4.1-mini',
        systemPrompt: 'SYSTEM',
        catalog: BasicCatalogItems.asCatalog(),
        httpClient: inner,
      );
      addTearDown(service.dispose);

      await service.runTurn(userText: 'a', surfaceId: 's0', tools: [_Tool()]);
      await service.runTurn(userText: 'b', surfaceId: 's1', tools: const []);

      expect(seen, hasLength(3));
      for (final req in seen) {
        expect(req.url, endpoint);
        expect(req.headers['Authorization'], 'Bearer user-jwt');
        expect(req.headers['apikey'], 'anon');
        expect(req.headers.values.join(), isNot(contains('sk-')));
      }
      final ids = [for (final r in seen) r.headers['x-porty-turn-id']];
      expect(ids[0], isNotNull);
      expect(ids[0], matches(RegExp(r'^[A-Za-z0-9_-]{8,64}$')));
      expect(ids[1], ids[0], reason: 'misma consulta, misma cuota');
      expect(ids[2], isNot(ids[0]), reason: 'turno nuevo, id nuevo');
    },
  );

  group('server typed errors', () {
    Future<Object?> errorFor(int status, Map<String, Object?> body) async {
      final client = AiProxyClient(
        AiProxyConfig.fixed(endpoint, 'jwt'),
        MockClient((_) async => http.Response(jsonEncode(body), status)),
      )..turnId = 'turn-12345678';
      try {
        final r = await client.send(
          http.Request('POST', Uri.parse('https://api.openai.com/v1/chat/completions'))
            ..body = '{}',
        );
        return r.statusCode;
      } catch (e) {
        return e;
      }
    }

    test('402 quota_exceeded → ProxyLimitException.isQuota', () async {
      final e = await errorFor(402, {
        'error': {'type': 'quota_exceeded', 'message': 'x'},
      });
      expect(e, isA<ProxyLimitException>().having((e) => e.isQuota, 'isQuota', true));
    });

    test('429 daily_limit → ProxyLimitException.isDailyLimit', () async {
      final e = await errorFor(429, {
        'error': {'type': 'daily_limit', 'message': 'x'},
      });
      expect(
        e,
        isA<ProxyLimitException>().having((e) => e.isDailyLimit, 'daily', true),
      );
    });

    test("OpenAI's own 429 passes through for the service to retry", () async {
      final e = await errorFor(429, {
        'error': {'message': 'Rate limit reached. Please try again in 2s.'},
      });
      expect(e, 429);
    });
  });
}
