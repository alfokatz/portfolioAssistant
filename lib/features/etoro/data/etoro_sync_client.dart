import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:portfolio_assistant/features/etoro/domain/etoro_connection.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';

/// Error tipado de la edge function `etoro-sync` (campo `error.type`):
/// `etoro_plan_required`, `etoro_reconnect_required`, `etoro_rate_limited`,
/// `etoro_unavailable`, `etoro_sync_in_progress`, `etoro_not_connected`…
/// `network` si no hubo respuesta.
class EtoroSyncException implements Exception {
  const EtoroSyncException(this.type, {this.retryAfterSeconds});

  final String type;
  final int? retryAfterSeconds;

  bool get isReconnectRequired => type == 'etoro_reconnect_required';
  bool get isPlanRequired => type == 'etoro_plan_required';

  @override
  String toString() => 'EtoroSyncException($type)';
}

/// Habla con la edge function `etoro-sync` con el JWT del usuario. Los
/// tokens de eToro nunca pasan por la app: viven cifrados en el servidor.
class EtoroSyncClient {
  EtoroSyncClient({
    Dio? dio,
    String? baseUrl,
    Future<String?> Function()? accessToken,
    String? anonKey,
  }) : _dio = dio ?? _createDio(),
       _baseUrl = baseUrl ?? _defaultBaseUrl(),
       _accessToken = accessToken ?? AiProxyConfig.supabaseAccessToken,
       _anonKey = anonKey ?? _env('SUPABASE_ANON_KEY');

  final Dio _dio;
  final String _baseUrl;
  final Future<String?> Function() _accessToken;
  final String? _anonKey;

  static String _defaultBaseUrl() {
    final supabase = _env('SUPABASE_URL') ?? '';
    return supabase.isEmpty ? '' : '$supabase/functions/v1/etoro-sync';
  }

  static String? _env(String name) {
    try {
      return dotenv.maybeGet(name)?.trim();
    } catch (_) {
      return null; // `.env` sin cargar (tests)
    }
  }

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        // Una sincronización trae portfolio, historial y metadata de eToro.
        receiveTimeout: const Duration(seconds: 45),
        validateStatus: (status) => status != null && status < 600,
      ),
    );
  }

  /// URL de autorización de eToro para abrir en el navegador del sistema.
  Future<Uri> startConnect() async {
    final data = await _post('/connect/start');
    final url = data['authorizeUrl'];
    if (url is! String) throw const EtoroSyncException('bad_response');
    return Uri.parse(url);
  }

  /// Sincroniza. `throttled`: el servidor devolvió la última (hubo una hace
  /// menos de 5 minutos).
  Future<({EtoroImportResult result, bool throttled})> sync() async {
    final data = await _post('/sync');
    final result = data['result'];
    if (result is! Map) throw const EtoroSyncException('bad_response');
    return (
      result: EtoroImportResult.fromJson(Map<String, dynamic>.from(result)),
      throttled: data['throttled'] == true,
    );
  }

  Future<void> disconnect({required bool keepAsManual}) async {
    await _post('/disconnect', body: {'keepAsManual': keepAsManual});
  }

  Future<Map<String, dynamic>> _post(String path, {Object? body}) async {
    if (_baseUrl.isEmpty) throw const EtoroSyncException('not_configured');
    final token = await _accessToken();
    final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        '$_baseUrl$path',
        data: body,
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            if (_anonKey != null) 'apikey': _anonKey,
          },
        ),
      );
    } on DioException {
      throw const EtoroSyncException('network');
    }
    final data = response.data;
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    if (response.statusCode == 200) return map;
    final error = map['error'];
    if (error is Map) {
      throw EtoroSyncException(
        (error['type'] as String?) ?? 'http_${response.statusCode}',
        retryAfterSeconds: (error['retryAfterSeconds'] as num?)?.toInt(),
      );
    }
    throw EtoroSyncException('http_${response.statusCode}');
  }
}
