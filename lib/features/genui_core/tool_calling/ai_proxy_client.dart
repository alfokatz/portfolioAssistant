import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Límite aplicado por el servidor (proxy `ai-chat`), con su tipo estable.
class ProxyLimitException implements Exception {
  const ProxyLimitException(this.type, [this.message = '']);

  /// `quota_exceeded` (cuota mensual), `daily_limit` (tope diario),
  /// `rate_limited`, `too_many_rounds`, `unauthorized`, `prompt_not_allowed`…
  final String type;
  final String message;

  bool get isQuota => type == 'quota_exceeded';
  bool get isDailyLimit => type == 'daily_limit';

  @override
  String toString() => 'ProxyLimitException($type): $message';
}

/// Dónde está el proxy y con qué credenciales de USUARIO se le habla. La key
/// de OpenAI nunca está en la app: la agrega el servidor.
class AiProxyConfig {
  const AiProxyConfig({
    required this.endpoint,
    required this.accessToken,
    this.anonKey,
  });

  /// La de la app: la edge function `ai-chat` del proyecto de Supabase del
  /// flavor activo y el JWT de la sesión (renovado si ya venció).
  factory AiProxyConfig.fromEnvironment() {
    final base = (dotenv.env['SUPABASE_URL'] ?? '').trim();
    return AiProxyConfig(
      endpoint: Uri.parse('$base/functions/v1/ai-chat'),
      anonKey: dotenv.env['SUPABASE_ANON_KEY']?.trim(),
      accessToken: supabaseAccessToken,
    );
  }

  /// Sesión fija (tests, evals contra el proxy local).
  factory AiProxyConfig.fixed(Uri endpoint, String token, {String? anonKey}) =>
      AiProxyConfig(
        endpoint: endpoint,
        anonKey: anonKey,
        accessToken: () async => token,
      );

  static Future<String?> supabaseAccessToken() async {
    try {
      final auth = Supabase.instance.client.auth;
      var session = auth.currentSession;
      if (session != null && session.isExpired) {
        session = (await auth.refreshSession()).session;
      }
      return session?.accessToken;
    } catch (_) {
      // Supabase sin inicializar o sin red para renovar: sin sesión.
      return null;
    }
  }

  /// `https://<proyecto>.supabase.co/functions/v1/ai-chat`
  final Uri endpoint;

  /// JWT de la sesión de Supabase (se lee en cada request: se renueva solo).
  final Future<String?> Function() accessToken;

  /// Anon key del proyecto (pública por diseño; la pide el gateway).
  final String? anonKey;
}

/// Redirige los requests de Chat Completions que arma `dart_openai` al proxy
/// `ai-chat`: cambia la URL, reemplaza la "API key" por el JWT del usuario y
/// agrega el `x-porty-turn-id` del turno en curso (el proxy cobra una
/// consulta por turn_id, no por request).
///
/// Los rechazos tipados del servidor (402 cuota, 429 tope diario…) se
/// convierten en [ProxyLimitException] acá, antes de que `dart_openai` los
/// vuelva un error genérico; el 429 de OpenAI (sin `error.type` nuestro) pasa
/// igual que siempre y lo reintenta el servicio.
class AiProxyClient extends http.BaseClient {
  AiProxyClient(this.config, [http.Client? inner])
    : _inner = inner ?? http.Client();

  final AiProxyConfig config;
  final http.Client _inner;

  /// Turno en curso: lo fija el servicio antes de cada ronda.
  String? turnId;

  static const _serverLimitTypes = {
    'quota_exceeded',
    'daily_limit',
    'rate_limited',
    'too_many_rounds',
    'turn_mismatch',
    'unauthorized',
    'prompt_not_allowed',
    'model_not_allowed',
    'body_too_large',
    'invalid_turn_id',
    'unavailable',
  };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!request.url.path.endsWith('/chat/completions') || request is! http.Request) {
      return _inner.send(request);
    }
    final token = await config.accessToken();
    if (token == null || token.isEmpty) {
      throw const ProxyLimitException('unauthorized', 'No hay sesión');
    }
    final proxied =
        http.Request(request.method, config.endpoint)
          ..headers.addAll({
            ...request.headers,
            'Authorization': 'Bearer $token',
            if (config.anonKey != null) 'apikey': config.anonKey!,
            if (turnId != null) 'x-porty-turn-id': turnId!,
          })
          ..body = request.body;
    final response = await _inner.send(proxied);
    if (response.statusCode < 400) return response;

    // Leer el cuerpo para decidir si es un rechazo NUESTRO; si no, se
    // devuelve intacto (p. ej. un 429 de OpenAI que el servicio reintenta).
    final bytes = await response.stream.toBytes();
    final type = _serverErrorType(bytes);
    if (type != null && _serverLimitTypes.contains(type)) {
      throw ProxyLimitException(type, utf8.decode(bytes, allowMalformed: true));
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      headers: response.headers,
      request: proxied,
      reasonPhrase: response.reasonPhrase,
    );
  }

  static String? _serverErrorType(List<int> bytes) {
    try {
      final body = jsonDecode(utf8.decode(bytes));
      final error = body is Map ? body['error'] : null;
      final type = error is Map ? error['type'] : null;
      return type is String ? type : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void close() => _inner.close();
}
