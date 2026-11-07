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

void main() {
  // Regresión (2026-10-01, "¿por qué bajó AMZN?"): la ronda 1 todavía tenía
  // tools habilitadas y por eso el tope corto de las rondas de tools; el
  // modelo escribió ahí la respuesta larga (~11 s), se cortó y el usuario
  // vio "No pude procesar tu consulta".
  test('an answer written in a round where tools are still allowed gets the '
      'full answer time', () async {
    const timeout = Duration(milliseconds: 600);
    var n = 0;
    final client = MockClient((_) async {
      n++;
      if (n == 1) {
        return _completion({
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {
              'id': 'c1',
              'type': 'function',
              'function': {'name': 'get_quote', 'arguments': '{}'},
            },
          ],
        });
      }
      // Respuesta "larga": tarda más de la mitad del tope.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return _completion({
        'role': 'assistant',
        'content':
            '{"version":"v0.9","createSurface":{"surfaceId":"s0",'
            '"catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}\n'
            '{"version":"v0.9","updateComponents":{"surfaceId":"s0",'
            '"components":[{"id":"root","component":"Text","text":"ok"}]}}',
      });
    });
    final service = OpenAIGenUiService(
      proxy: AiProxyConfig.fixed(Uri.parse('https://proxy.test'), 'jwt'),
      model: 'gpt-4.1-mini',
      systemPrompt: 'SYSTEM',
      catalog: BasicCatalogItems.asCatalog(),
      httpClient: client,
      roundTimeout: timeout,
    );
    addTearDown(service.dispose);

    final outcome = await service.runTurn(
      userText: 'por qué bajó AMZN',
      surfaceId: 's0',
      tools: [_Tool()],
    );

    expect(n, 2);
    expect(outcome.ran('get_quote'), isTrue);
    expect(service.log.currentTurn!.finalText, contains('"text":"ok"'));
  });

  test('every round uses the same answer timeout by default', () {
    expect(OpenAIGenUiService.defaultRoundTimeout, const Duration(seconds: 25));
  });
}
