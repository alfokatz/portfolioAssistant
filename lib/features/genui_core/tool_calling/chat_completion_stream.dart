import 'dart:async';
import 'dart:convert';

import 'package:dart_openai/dart_openai.dart';
import 'package:http/http.dart' as http;

/// Texto de la respuesta acumulado hasta ahora (crece con cada chunk).
typedef ContentDeltaCallback = void Function(String contentSoFar);

/// Por qué terminó la respuesta (`stop`, `tool_calls`, `length`…).
typedef FinishReasonCallback = void Function(String finishReason);

/// Un request de Chat Completions con `stream: true`, leído a medida que
/// llega. Devuelve el mismo mensaje que `OpenAI.instance.chat.create` (texto
/// y tool calls armados con `fromMap`), así el loop de tools no cambia: lo
/// único nuevo es [onContent], que ve el texto mientras se escribe.
///
/// Va por el mismo [client] que el request sin streaming (proxy `ai-chat`,
/// patch del body). Los errores tienen la misma forma:
/// [RequestFailedException] con el mensaje y el status de OpenAI (el
/// servicio reintenta el 429 igual que antes), y los rechazos tipados del
/// proxy siguen saliendo como `ProxyLimitException` desde [client].
abstract final class ChatCompletionStream {
  /// Solo importa el path: `AiProxyClient` reconoce `/chat/completions` y
  /// lo manda al proxy `ai-chat` (la app nunca habla con OpenAI directo).
  static final _url = Uri.parse('https://ai-chat.proxy/v1/chat/completions');

  static Future<OpenAIChatCompletionChoiceMessageModel> create({
    required http.Client client,
    required String model,
    required List<OpenAIChatCompletionChoiceMessageModel> messages,
    List<OpenAIToolModel>? tools,
    Object? toolChoice,
    double? temperature,
    ContentDeltaCallback? onContent,
    FinishReasonCallback? onFinish,
  }) async {
    final request =
        http.Request('POST', _url)
          ..headers['Content-Type'] = 'application/json'
          // dart_openai arma el header con su key; el proxy lo reemplaza por
          // el JWT del usuario antes de salir del dispositivo.
          ..headers['Authorization'] = 'Bearer proxy'
          ..body = jsonEncode({
            'model': model,
            'messages': [for (final m in messages) m.toMap()],
            if (tools != null) 'tools': [for (final t in tools) t.toMap()],
            if (toolChoice != null) 'tool_choice': toolChoice,
            if (temperature != null) 'temperature': temperature,
            'stream': true,
          });
    final response = await client.send(request);
    if (response.statusCode >= 400) {
      final body = await response.stream.bytesToString();
      throw RequestFailedException(_errorMessage(body), response.statusCode);
    }

    final content = StringBuffer();
    final calls = <int, _ToolCallParts>{};
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      final Object? chunk;
      try {
        chunk = jsonDecode(data);
      } catch (_) {
        continue;
      }
      if (chunk is! Map) continue;
      final error = chunk['error'];
      if (error is Map) {
        throw RequestFailedException('${error['message'] ?? error}', 500);
      }
      final choices = chunk['choices'];
      if (choices is! List || choices.isEmpty) continue; // chunk de usage
      final choice = choices.first as Map;
      final finish = choice['finish_reason'];
      if (finish is String) onFinish?.call(finish);
      final delta = choice['delta'];
      if (delta is! Map) continue;
      final text = delta['content'];
      if (text is String && text.isNotEmpty) {
        content.write(text);
        onContent?.call(content.toString());
      }
      final toolCalls = delta['tool_calls'];
      if (toolCalls is List) {
        for (final raw in toolCalls.whereType<Map>()) {
          final index = (raw['index'] as num?)?.toInt() ?? calls.length;
          final parts = calls.putIfAbsent(index, _ToolCallParts.new);
          parts.add(raw);
        }
      }
    }

    final ordered = calls.keys.toList()..sort();
    return OpenAIChatCompletionChoiceMessageModel.fromMap({
      'role': 'assistant',
      'content': content.isEmpty ? null : content.toString(),
      if (ordered.isNotEmpty)
        'tool_calls': [for (final i in ordered) calls[i]!.toMap()],
    });
  }

  static String _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      final error = decoded is Map ? decoded['error'] : null;
      if (error is Map && error['message'] != null)
        return '${error['message']}';
    } catch (_) {
      // cuerpo que no es JSON: va tal cual
    }
    return body;
  }
}

/// Una tool call llega en pedazos: el id y el nombre en el primero, los
/// argumentos (JSON en texto) repartidos en varios.
class _ToolCallParts {
  String? id;
  String type = 'function';
  final name = StringBuffer();
  final arguments = StringBuffer();

  void add(Map<dynamic, dynamic> delta) {
    id ??= delta['id'] as String?;
    if (delta['type'] is String) type = delta['type'] as String;
    final function = delta['function'];
    if (function is Map) {
      if (function['name'] is String) name.write(function['name']);
      if (function['arguments'] is String) {
        arguments.write(function['arguments']);
      }
    }
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'type': type,
    'function': {'name': name.toString(), 'arguments': arguments.toString()},
  };
}
