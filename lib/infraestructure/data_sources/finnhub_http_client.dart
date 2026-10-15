import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';

/// Cliente HTTP compartido para Finnhub (calendario de resultados,
/// noticias, fundamentals…). Habla con la edge function `finnhub` de
/// Supabase, que agrega la key del servidor, cachea para todos los
/// usuarios y aplica rate limit: la app nunca tiene la key de Finnhub.
///
/// Solo arma la request; los repos que lo usan son responsables de
/// convertir cualquier `DioException`/error a `Either<HttpError, T>` —
/// este cliente no interpreta el body.
class FinnhubHttpClient {
  FinnhubHttpClient({
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
    return supabase.isEmpty ? '' : '$supabase/functions/v1/finnhub';
  }

  static String? _env(String name) {
    try {
      return dotenv.maybeGet(name)?.trim();
    } catch (_) {
      return null; // `.env` sin cargar (tests)
    }
  }

  /// Hay proxy al que pedirle (sin `SUPABASE_URL`, las fuentes Finnhub se
  /// dan por no disponibles, como antes sin key).
  bool get isConfigured => _baseUrl.isNotEmpty;

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (status) => status != null && status < 500,
      ),
    );
  }

  /// [path] es el del endpoint de Finnhub (`/company-news`, …): el proxy
  /// solo acepta los de su allowlist.
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final token = await _accessToken();
    return _dio.get<dynamic>(
      '$_baseUrl$path',
      queryParameters: queryParameters,
      options: Options(
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          if (_anonKey != null) 'apikey': _anonKey,
        },
      ),
    );
  }

  /// Formato `YYYY-MM-DD` que esperan los endpoints `from`/`to` de Finnhub.
  static String formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
