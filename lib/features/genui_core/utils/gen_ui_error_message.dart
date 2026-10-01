import 'dart:async';
import 'dart:io';

import 'package:dart_openai/dart_openai.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';

/// Convierte errores técnicos de OpenAI/GenUI en mensajes legibles para el usuario.
String genUiErrorMessage(Object error) {
  if (error is A2uiValidationException) {
    return 'La IA devolvió un formato de UI inválido. Intentá de nuevo.';
  }
  if (error is RequestFailedException) {
    return _fromRequestFailed(error);
  }
  if (error is ProxyLimitException) {
    return _fromProxy(error);
  }

  final text = error.toString();

  if (error is StateError && text.contains('búsqueda web')) {
    return text.replaceFirst('Bad state: ', '');
  }

  if (error is StateError && text.contains('interfaz válida')) {
    return text.replaceFirst('Bad state: ', '');
  }

  if (error is TimeoutException) {
    return error.message ??
        'La IA no generó una interfaz a tiempo. Revisá tu conexión o intentá de nuevo.';
  }

  if (_looksLikeRateLimit(text)) {
    return _rateLimitMessage(retrySeconds: _extractRetrySeconds(text));
  }

  return _generic;
}

// La key y la facturación de OpenAI son del servidor: el usuario nunca ve
// mensajes sobre ellas (antes decían "revisá tu .env" o "tu cuenta de
// OpenAI").
const _generic =
    'No pudimos obtener una respuesta de la IA. Intentá de nuevo en unos segundos.';
const _serviceDown =
    'Porty tuvo un problema temporal. Intentá de nuevo en un momento.';

/// Rechazos del proxy `ai-chat`. La cuota (paywall) y el tope diario
/// (aviso discreto) los resuelve el provider antes de llegar acá.
String _fromProxy(ProxyLimitException error) {
  switch (error.type) {
    case 'quota_exceeded':
      return 'Usaste todas las consultas de tu plan este mes.';
    case 'daily_limit':
      return 'Volvés a tener consultas mañana.';
    case 'rate_limited':
    case 'too_many_rounds':
      return 'Estás enviando muchas consultas seguidas. Esperá unos segundos y reenviá tu consulta.';
    case 'unauthorized':
      return 'Tu sesión venció. Volvé a iniciar sesión para seguir usando Porty.';
    case 'unavailable':
      return _serviceDown;
    default:
      return _generic;
  }
}

String _fromRequestFailed(RequestFailedException error) {
  final message = error.message;
  final code = error.statusCode;

  switch (code) {
    case 429:
      if (_looksLikeQuota(message)) return _serviceDown;
      return _rateLimitMessage(retrySeconds: _extractRetrySeconds(message));
    case 401:
    case 402:
    case 403:
    case 500:
    case 502:
    case 503:
      return _serviceDown;
    default:
      return _generic;
  }
}

bool _looksLikeRateLimit(String text) {
  final lower = text.toLowerCase();
  return lower.contains('rate limit') ||
      lower.contains('rate_limit') ||
      lower.contains('tokens per min') ||
      lower.contains('tpm') ||
      lower.contains('requests per min') ||
      lower.contains('rpm') ||
      lower.contains('too many requests') ||
      lower.contains('demasiadas solicitudes') ||
      lower.contains('"code":429') ||
      lower.contains('status code: 429');
}

bool _looksLikeQuota(String text) {
  final lower = text.toLowerCase();
  return lower.contains('insufficient_quota') ||
      lower.contains('exceeded your current quota') ||
      lower.contains('billing') && lower.contains('quota');
}

String _rateLimitMessage({int? retrySeconds}) {
  final wait = retrySeconds != null && retrySeconds > 0
      ? ' Esperá unos $retrySeconds segundos'
      : ' Esperá unos 5–10 segundos';
  return 'Porty está recibiendo muchas consultas (límite de uso por minuto).$wait y reenviá tu consulta.';
}

/// Segundos sugeridos por OpenAI antes de reintentar (p. ej. rate limit 429).
int? openAiSuggestedRetrySeconds(String text) {
  return _extractRetrySeconds(text);
}

/// Indica si el error es un rate limit (429 TPM/RPM).
bool isOpenAiRateLimitError(Object error) {
  if (error is RequestFailedException) {
    return error.statusCode == 429 || _looksLikeRateLimit(error.message);
  }
  return _looksLikeRateLimit(error.toString());
}

/// Distingue una falla de **conexión real** (sin internet, DNS, conexión
/// rechazada) de una falla de **generación** (el modelo tardó, devolvió
/// JSON inválido, o el resultado reparado no tenía componente raíz).
///
/// Solo `SocketException` cuenta como falla de conexión — todo lo demás
/// (timeout tras agotar el reintento, `StateError`/`A2uiValidationException`
/// de esquema inválido, cualquier `RequestFailedException`) es una falla
/// de generación: no amerita el banner de error, cae a una respuesta de
/// texto simple en su lugar (ver `AssistantProvider.sendMessage`).
bool isConnectionFailure(Object error) => error is SocketException;

int? _extractRetrySeconds(String text) {
  final tryAgainSeconds = RegExp(
    r'try again in\s+(\d+(?:\.\d+)?)\s*s',
    caseSensitive: false,
  ).firstMatch(text);
  if (tryAgainSeconds != null) {
    final seconds = double.tryParse(tryAgainSeconds.group(1)!);
    if (seconds != null) return seconds.ceil().clamp(1, 120);
  }

  final retryAfterMs = RegExp(
    r'retry[- ]?after[^0-9]*(\d+)\s*ms',
    caseSensitive: false,
  ).firstMatch(text);
  if (retryAfterMs != null) {
    final ms = int.tryParse(retryAfterMs.group(1)!);
    if (ms != null) return ((ms / 1000).ceil()).clamp(1, 120);
  }

  final retryAfterSeconds = RegExp(
    r'retry[- ]?after[^0-9]*(\d+(?:\.\d+)?)\s*s',
    caseSensitive: false,
  ).firstMatch(text);
  if (retryAfterSeconds != null) {
    final seconds = double.tryParse(retryAfterSeconds.group(1)!);
    if (seconds != null) return seconds.ceil().clamp(1, 120);
  }

  return null;
}
