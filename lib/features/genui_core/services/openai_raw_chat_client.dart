import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';
import 'package:portfolio_assistant/features/genui_core/utils/openai_request_throttle.dart';

/// Cliente HTTP directo para la Responses API de OpenAI (web search).
class OpenAIRawChatClient {
  OpenAIRawChatClient({
    Dio? dio,
    String? apiKey,
    String? model,
  })  : _dio = dio ?? Dio(),
        _apiKey = apiKey ?? dotenv.env['OPENAI_API_KEY'] ?? '',
        _model = model ??
            dotenv.env['OPENAI_NEWS_MODEL'] ??
            dotenv.env['OPENAI_MODEL'] ??
            OpenAIGenUiService.defaultModel;

  final Dio _dio;
  final String _apiKey;
  final String _model;

  static const _responsesUrl = 'https://api.openai.com/v1/responses';

  /// Fase 1: búsqueda web con `web_search` en Responses API (non-streaming).
  Future<String> searchNews({
    required String userQuery,
    required List<String> tickers,
  }) async {
    if (_apiKey.isEmpty) {
      throw StateError('OPENAI_API_KEY no configurada');
    }

    final tickerList = tickers.isEmpty ? 'ninguno' : tickers.join(', ');
    final instructions = '''
You are a financial news researcher. Use web search to find recent, real news.

Portfolio tickers: $tickerList

Return a structured text summary of each relevant story found:
- headline
- source (publisher name)
- publishedAt (relative time, e.g. "hace 2 horas")
- url (full URL if available)
- affected tickers
- 2-3 sentence summary

If no recent news is found for a ticker, state that explicitly.
NEVER fabricate headlines, sources, or URLs. Only report what search returns.
''';

    for (var attempt = 0; attempt <= OpenAIGenUiService.maxRateLimitRetries; attempt++) {
      try {
        return await _postResponses(
          instructions: instructions,
          input: userQuery,
        );
      } on DioException catch (e) {
        final canRetry = _isRateLimit(e) && attempt < OpenAIGenUiService.maxRateLimitRetries;
        if (!canRetry) throw _mapDioError(e);
        final seconds = openAiSuggestedRetrySeconds(e.message ?? '') ?? 5;
        await Future<void>.delayed(
          Duration(milliseconds: ((seconds + 1) * 1000).clamp(2000, 120000)),
        );
      }
    }

    throw StateError('No se pudo completar la búsqueda de noticias');
  }

  Future<String> _postResponses({
    required String instructions,
    required String input,
  }) async {
    await OpenAiRequestThrottle.waitIfNeeded();
    OpenAiRequestThrottle.markRequestStarted();

    final response = await _dio.post<Map<String, dynamic>>(
      _responsesUrl,
      options: Options(
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
      ),
      data: {
        'model': _model,
        'instructions': instructions,
        'input': input,
        'tools': [
          {
            'type': 'web_search',
            'search_context_size': 'medium',
          },
        ],
        'tool_choice': 'required',
        'include': ['web_search_call.action.sources'],
      },
    );

    final data = response.data;
    if (data == null) {
      throw StateError('Respuesta vacía de OpenAI');
    }

    final apiError = data['error'];
    if (apiError is Map) {
      final message = apiError['message'] as String? ?? 'Error desconocido';
      throw StateError('Error en búsqueda web: $message');
    }

    final status = data['status'] as String?;
    if (status == 'failed' || status == 'incomplete') {
      final details = data['incomplete_details'];
      throw StateError(
        'La búsqueda web no se completó (${status ?? 'unknown'}): $details',
      );
    }

    final text = extractResponsesOutputText(data);
    if (text.isEmpty) {
      throw StateError('OpenAI no devolvió contenido de búsqueda');
    }
    return text;
  }

  /// Extrae el texto de una respuesta de la Responses API.
  static String extractResponsesOutputText(Map<String, dynamic> data) {
    final buffer = StringBuffer();

    final topLevel = data['output_text'];
    if (topLevel is String && topLevel.trim().isNotEmpty) {
      buffer.write(topLevel.trim());
    }

    final output = data['output'];
    if (output is List) {
      for (final item in output) {
        if (item is! Map<String, dynamic>) continue;

        if (item['type'] == 'message') {
          final content = item['content'];
          if (content is List) {
            for (final part in content) {
              if (part is Map && part['type'] == 'output_text') {
                final text = part['text'] as String?;
                if (text != null && text.trim().isNotEmpty) {
                  if (buffer.isNotEmpty) buffer.writeln();
                  buffer.write(text.trim());
                }
              }
            }
          }
        }

        if (item['type'] == 'web_search_call') {
          final action = item['action'];
          if (action is Map) {
            final sources = action['sources'];
            if (sources is List && sources.isNotEmpty) {
              buffer.writeln('\n\nSources:');
              for (final source in sources) {
                if (source is Map) {
                  final url = source['url'] as String?;
                  if (url != null) buffer.writeln('- $url');
                }
              }
            }
          }
        }
      }
    }

    return buffer.toString().trim();
  }

  bool _isRateLimit(DioException e) {
    if (e.response?.statusCode == 429) return true;
    return isOpenAiRateLimitError(e.message ?? e.toString());
  }

  Object _mapDioError(DioException e) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    final message = body is Map
        ? (body['error']?['message'] as String? ?? e.message ?? '')
        : (e.message ?? e.toString());

    if (status == 429 || isOpenAiRateLimitError(message)) {
      return StateError('Rate limit OpenAI: $message');
    }
    if (status == 401) {
      return StateError('API key inválida: $message');
    }
    if (status == 400 && message.toLowerCase().contains('web_search')) {
      return StateError(
        'Tu cuenta o modelo no soporta búsqueda web: $message',
      );
    }
    return StateError('Error en búsqueda web: $message');
  }
}
