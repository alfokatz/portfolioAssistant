import 'dart:convert';

import 'package:http/http.dart' as http;

/// Completa el body de los requests de Chat Completions con parámetros que
/// `dart_openai` 5.1.0 no expone (su body es un mapa fijo; ver
/// `OpenAIChat.create`):
/// - `store: false` — Chat Completions se guarda por defecto en cuentas
///   nuevas, y acá viaja la cartera del usuario;
/// - `parallel_tool_calls: true` cuando hay tools (es el default de la API,
///   explícito para que no dependa de eso).
///
/// Solo toca requests JSON a `/chat/completions`; todo lo demás pasa igual.
class OpenAiBodyPatchClient extends http.BaseClient {
  OpenAiBodyPatchClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request is! http.Request ||
        !request.url.path.endsWith('/chat/completions')) {
      return _inner.send(request);
    }
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(request.body) as Map<String, dynamic>;
    } catch (_) {
      return _inner.send(request);
    }
    body['store'] = false;
    if (body['tools'] is List && (body['tools'] as List).isNotEmpty) {
      body['parallel_tool_calls'] = true;
    }
    final patched =
        http.Request(request.method, request.url)
          ..headers.addAll(request.headers)
          ..body = jsonEncode(body);
    return _inner.send(patched);
  }

  @override
  void close() => _inner.close();
}
