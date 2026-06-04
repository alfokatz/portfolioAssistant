import 'package:dart_openai/dart_openai.dart';
import 'package:genui/genui.dart';

/// Convierte errores técnicos de OpenAI/GenUI en mensajes legibles para el usuario.
String genUiErrorMessage(Object error) {
  if (error is A2uiValidationException) {
    return 'La IA devolvió un formato de UI inválido. Intentá de nuevo.';
  }
  if (error is RequestFailedException) {
    return _fromRequestFailed(error);
  }
  if (error is MissingApiKeyException) {
    return 'Falta configurar la API key de OpenAI. Revisá el archivo .env de la app.';
  }

  final text = error.toString();

  if (error is StateError && text.contains('OPENAI_API_KEY')) {
    return 'Falta configurar OPENAI_API_KEY en el archivo .env.';
  }

  if (error is StateError && text.contains('búsqueda web')) {
    return text.replaceFirst('Bad state: ', '');
  }

  if (_looksLikeRateLimit(text)) {
    return _rateLimitMessage(retrySeconds: _extractRetrySeconds(text));
  }

  if (_looksLikeQuota(text)) {
    return 'No hay crédito disponible en tu cuenta de OpenAI. '
        'Revisá facturación en platform.openai.com.';
  }

  return 'No pudimos obtener una respuesta de la IA. Intentá de nuevo en unos segundos.';
}

String _fromRequestFailed(RequestFailedException error) {
  final message = error.message;
  final code = error.statusCode;

  switch (code) {
    case 429:
      return _rateLimitMessage(retrySeconds: _extractRetrySeconds(message));
    case 401:
      return 'La API key de OpenAI no es válida. Verificá OPENAI_API_KEY en tu .env.';
    case 402:
    case 403:
      if (_looksLikeQuota(message)) {
        return 'No hay crédito disponible en tu cuenta de OpenAI. '
            'Revisá facturación en platform.openai.com.';
      }
      return 'No tenés permiso para usar este modelo o tu cuenta tiene un límite activo.';
    case 500:
    case 502:
    case 503:
      return 'OpenAI tuvo un problema temporal. Intentá de nuevo en un momento.';
    default:
      break;
  }

  if (_looksLikeQuota(message)) {
    return 'No hay crédito disponible en tu cuenta de OpenAI. '
        'Revisá facturación en platform.openai.com.';
  }

  return 'No pudimos obtener una respuesta de la IA. Intentá de nuevo en unos segundos.';
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
  return 'Llegaste al límite de uso por minuto de OpenAI (no es falta de crédito).$wait y tocá actualizar o reenviá tu consulta.';
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
