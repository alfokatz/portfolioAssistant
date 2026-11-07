import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';

/// Respuesta de una edge function de datos: el status HTTP y el body JSON
/// (o `null` si no hubo respuesta).
class EdgeResponse {
  const EdgeResponse(this.statusCode, this.body);

  /// 0 = no se pudo hablar con el servidor (red, timeout, sin configurar).
  final int statusCode;
  final Map<String, Object?>? body;

  bool get ok => statusCode == 200 && body != null;

  /// El `error.type` tipado del servidor (`plan_required`, `daily_limit`…).
  String? get errorType {
    final error = body?['error'];
    return error is Map ? error['type'] as String? : null;
  }

  /// El servidor dijo que el dato no está en el plan (403 plan_required).
  bool get planRequired => statusCode == 403 && errorType == 'plan_required';
}

/// Cliente de las edge functions de datos con uso comercial (`sec`,
/// `headlines`, `news-context`): manda el JWT de la sesión, nunca tira y
/// devuelve el status para que quien lo usa distinga "sin dato", "falló" y
/// "no está en el plan".
class PortyEdgeClient {
  PortyEdgeClient({
    Dio? dio,
    String? baseUrl,
    Future<String?> Function()? accessToken,
    String? anonKey,
    String? region,
  }) : _dio = dio ?? _createDio(),
       _region = region ?? AiProxyConfig.functionsRegion(),
       _baseUrl = baseUrl ?? _defaultBaseUrl(),
       _accessToken = accessToken ?? AiProxyConfig.supabaseAccessToken,
       _anonKey = anonKey ?? _env('SUPABASE_ANON_KEY');

  final Dio _dio;
  final String _baseUrl;
  final Future<String?> Function() _accessToken;
  final String? _anonKey;
  final String? _region;

  static String _defaultBaseUrl() {
    final supabase = _env('SUPABASE_URL') ?? '';
    return supabase.isEmpty ? '' : '$supabase/functions/v1';
  }

  static String? _env(String name) {
    try {
      return dotenv.maybeGet(name)?.trim();
    } catch (_) {
      return null; // `.env` sin cargar (tests)
    }
  }

  static Dio _createDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      // La búsqueda web de noticias tarda ~10 s; la SEC, 1-3 s sin caché.
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (status) => status != null && status < 600,
    ),
  );

  bool get isConfigured => _baseUrl.isNotEmpty;

  Future<EdgeResponse> get(
    String path, {
    Map<String, String> query = const {},
  }) => _send('GET', path, query: query);

  Future<EdgeResponse> post(
    String path,
    Map<String, Object?> body, {
    String? turnId,
  }) => _send('POST', path, body: body, turnId: turnId);

  Future<EdgeResponse> _send(
    String method,
    String path, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
    String? turnId,
  }) async {
    if (!isConfigured) return const EdgeResponse(0, null);
    try {
      final token = await _accessToken();
      final response = await _dio.request<dynamic>(
        '$_baseUrl/$path',
        queryParameters: query.isEmpty ? null : query,
        data: body,
        options: Options(
          method: method,
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            if (_anonKey != null) 'apikey': _anonKey,
            if (turnId != null) 'x-porty-turn-id': turnId,
            if (_region != null) 'x-region': _region,
          },
        ),
      );
      final data = response.data;
      return EdgeResponse(
        response.statusCode ?? 0,
        data is Map ? data.cast<String, Object?>() : null,
      );
    } catch (_) {
      return const EdgeResponse(0, null);
    }
  }
}
