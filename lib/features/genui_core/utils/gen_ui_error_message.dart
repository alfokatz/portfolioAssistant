import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';

/// Convierte errores técnicos de OpenAI/GenUI en mensajes legibles para el usuario.
String genUiErrorMessage(Object error) {
  if (error is A2uiValidationException) {
    return 'qa_gu_invalid_format'.tr();
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

  if (error is StateError && (text.contains('interfaz válida') ||
          text.contains('qa_gu_no_valid_ui'.tr()) ||
          text.contains('qa_gu_no_valid_ui_detail'.tr(namedArgs: {'error': ''})))) {
    return text.replaceFirst('Bad state: ', '');
  }

  if (error is TimeoutException) {
    return error.message ?? 'qa_gu_timeout'.tr();
  }

  if (_looksLikeRateLimit(text)) {
    return _rateLimitMessage(retrySeconds: _extractRetrySeconds(text));
  }

  return _generic;
}

// La key y la facturación de OpenAI son del servidor: el usuario nunca ve
// mensajes sobre ellas (antes decían "revisá tu .env" o "tu cuenta de
// OpenAI").
String get _generic => 'qa_gu_generic'.tr();
String get _serviceDown => 'qa_gu_service_down'.tr();

/// Rechazos del proxy `ai-chat`. La cuota (paywall) y el tope diario
/// (aviso discreto) los resuelve el provider antes de llegar acá.
String _fromProxy(ProxyLimitException error) {
  switch (error.type) {
    case 'quota_exceeded':
      return 'qa_gu_quota'.tr();
    case 'daily_limit':
      return 'qa_gu_daily'.tr();
    case 'rate_limited':
    case 'too_many_rounds':
      return 'qa_gu_rate'.tr();
    case 'unauthorized':
      return 'qa_gu_unauthorized'.tr();
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
      ? 'qa_gu_wait_seconds'.tr(namedArgs: {'seconds': '$retrySeconds'})
      : 'qa_gu_wait_default'.tr();
  return 'qa_gu_rate_limit'.tr(namedArgs: {'wait': wait});
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
