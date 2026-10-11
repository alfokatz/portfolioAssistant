import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';

/// Búsqueda web de Porty: habla con la edge function `web-search`, que
/// tiene la key, cachea para todos y aplica el tope diario del plan. La
/// respuesta ya viene en el formato del resultado de la tool `search_web`.
class WebSearchClient {
  WebSearchClient({
    Dio? dio,
    String? url,
    Future<String?> Function()? accessToken,
    String? anonKey,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 8),
               // Buscar y resumir tarda más que un dato de mercado.
               receiveTimeout: const Duration(seconds: 25),
               validateStatus: (status) => status != null && status < 600,
             ),
           ),
       _url = url ?? _defaultUrl(),
       _accessToken = accessToken ?? AiProxyConfig.supabaseAccessToken,
       _anonKey = anonKey ?? _env('SUPABASE_ANON_KEY');

  final Dio _dio;
  final String _url;
  final Future<String?> Function() _accessToken;
  final String? _anonKey;

  static String _defaultUrl() {
    final supabase = _env('SUPABASE_URL') ?? '';
    return supabase.isEmpty ? '' : '$supabase/functions/v1/web-search';
  }

  static String? _env(String name) {
    try {
      return dotenv.maybeGet(name)?.trim();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>> search(String query) async {
    if (_url.isEmpty) return const {'status': 'failed'};
    try {
      final token = await _accessToken();
      final response = await _dio.post<dynamic>(
        _url,
        data: {'query': query},
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            if (_anonKey != null) 'apikey': _anonKey,
          },
        ),
      );
      final body = response.data;
      if (response.statusCode == 200 && body is Map) {
        return body.cast<String, Object?>();
      }
      final error = body is Map ? body['error'] : null;
      final type = error is Map ? error['type'] : null;
      if (type == 'daily_limit') {
        return const {'status': 'limit', 'reason': 'daily_limit'};
      }
      return const {'status': 'failed'};
    } catch (_) {
      return const {'status': 'failed'};
    }
  }
}
