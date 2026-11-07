import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';

/// Cliente de Yahoo Finance `quoteSummary` (composición de ETFs, perfil de
/// compañía). Habla con la edge function `yahoo` de Supabase, que arma la
/// sesión cookie + crumb que Yahoo exige, cachea para todos los usuarios y
/// sirve el último dato si Yahoo limita: pedido desde el teléfono, Yahoo
/// respondía 401/429 y el dato llegaba vacío.
///
/// Solo arma la request; quien lo usa interpreta el body y convierte
/// cualquier error en "sin dato".
class YahooProxyClient {
  YahooProxyClient({
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
    return supabase.isEmpty ? '' : '$supabase/functions/v1/yahoo';
  }

  static String? _env(String name) {
    try {
      return dotenv.maybeGet(name)?.trim();
    } catch (_) {
      return null; // `.env` sin cargar (tests)
    }
  }

  bool get isConfigured => _baseUrl.isNotEmpty;

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        // El proxy puede reintentar contra Yahoo antes de responder.
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
        validateStatus: (status) => status != null && status < 600,
      ),
    );
  }

  /// `quoteSummary` de [symbol] (ya en formato Yahoo) con [modules] — solo
  /// los de la allowlist del proxy. Devuelve el primer `result`, o `null`
  /// si Yahoo no tiene el símbolo (404 / result vacío).
  ///
  /// Lanza [YahooUnavailableException] si no se pudo consultar (red, 429,
  /// proxy caído): "no hay dato" y "no se pudo traer" son distintos para el
  /// modelo (`empty` vs `failed`).
  Future<Map<String, dynamic>?> quoteSummary(
    String symbol,
    List<String> modules,
  ) async {
    if (!isConfigured) throw const YahooUnavailableException('not_configured');
    final token = await _accessToken();
    final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(
        '$_baseUrl/quote-summary',
        queryParameters: {'symbol': symbol, 'modules': modules.join(',')},
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            if (_anonKey != null) 'apikey': _anonKey,
          },
        ),
      );
    } on DioException catch (e) {
      throw YahooUnavailableException(e.type.name);
    }
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw YahooUnavailableException('http_${response.statusCode}');
    }
    final results = switch (response.data) {
      {'quoteSummary': {'result': final List results}} => results,
      _ => null,
    };
    if (results == null || results.isEmpty) return null;
    final first = results.first;
    return first is Map<String, dynamic> ? first : null;
  }

  /// Yahoo manda los números como `{"raw": 1.2, "fmt": "1.20"}`.
  static double? number(Object? value) => switch (value) {
    {'raw': final num raw} => raw.toDouble(),
    final num raw => raw.toDouble(),
    _ => null,
  };
}

class YahooUnavailableException implements Exception {
  const YahooUnavailableException(this.reason);

  final String reason;

  @override
  String toString() => 'YahooUnavailableException($reason)';
}
