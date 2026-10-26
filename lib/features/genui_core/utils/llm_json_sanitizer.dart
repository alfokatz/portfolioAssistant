import 'dart:convert';

import 'package:portfolio_assistant/features/genui_core/utils/a2ui_response_normalizer.dart';

/// Extrae bloques JSON válidos de respuestas verbosas de GPT-4o.
abstract final class LlmJsonSanitizer {
  static const defaultFallbackMessage =
      'No pude procesar tu consulta. Intentá reformularla.';

  /// Sanitiza [raw] extrayendo JSON parseable. Devuelve string vacío si no hay nada.
  static String sanitize(String raw) {
    final trimmed = _stripMarkdown(raw.trim());
    if (trimmed.isEmpty) return trimmed;

    final objects = _extractValidJsonChunks(trimmed);
    if (objects.isEmpty) return trimmed;
    return objects.join('\n');
  }

  /// Sanitiza [raw] o devuelve fallback A2UI si no hay JSON válido.
  static String sanitizeOrFallback(
    String raw, {
    required String surfaceId,
    String fallbackMessage = defaultFallbackMessage,
    String catalogId = A2uiResponseNormalizer.defaultCatalogId,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return A2uiResponseNormalizer.fallbackResponse(
        surfaceId,
        fallbackMessage,
        catalogId: catalogId,
      );
    }

    final sanitized = sanitize(trimmed);
    if (sanitized.isEmpty || !_hasParseableJson(sanitized)) {
      // El modelo contestó en texto plano (pasa con repreguntas cortas,
      // "¿cuál querés seguir?"): se muestra ese texto, no se tira la
      // respuesta. El mensaje genérico queda para lo que de verdad no se
      // puede leer (JSON roto).
      final prose = plainText(trimmed);
      return A2uiResponseNormalizer.fallbackResponse(
        surfaceId,
        prose ?? fallbackMessage,
        catalogId: catalogId,
      );
    }

    return sanitized;
  }

  /// [raw] no deja nada para mostrar: vacío, o un JSON roto (cortado por
  /// el tope de salida) que tampoco sirve como texto. Es lo que termina en
  /// [defaultFallbackMessage].
  static bool isUnreadable(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return true;
    final sanitized = sanitize(trimmed);
    if (sanitized.isNotEmpty && _hasParseableJson(sanitized)) return false;
    return plainText(trimmed) == null;
  }

  /// [raw] como texto para mostrar si es prosa y no un JSON roto; `null` si
  /// no sirve (vacío, con llaves o restos de componentes, o muy largo).
  static String? plainText(String raw) {
    final text = _stripMarkdown(raw).trim();
    if (text.isEmpty || text.length > 1200) return null;
    if (text.contains('{') ||
        text.contains('}') ||
        text.contains('"component"') ||
        text.contains('updateComponents')) {
      return null;
    }
    return text;
  }

  static bool _hasParseableJson(String text) {
    final chunks = _extractValidJsonChunks(text);
    return chunks.isNotEmpty;
  }

  static String _stripMarkdown(String text) {
    return text
        .replaceAll('```json', '')
        .replaceAll('```dart', '')
        .replaceAll('```', '')
        .trim();
  }

  static List<String> _extractValidJsonChunks(String text) {
    final results = <String>[];
    var remaining = text;

    while (remaining.isNotEmpty) {
      remaining = remaining.trimLeft();
      if (remaining.isEmpty) break;

      final markdownMatch = _markdownPattern.firstMatch(remaining);
      if (markdownMatch != null && markdownMatch.start == 0) {
        final content = markdownMatch.group(1)?.trim();
        if (content != null && content.isNotEmpty) {
          final nested = _extractValidJsonChunks(content);
          results.addAll(nested);
        }
        remaining = remaining.substring(markdownMatch.end);
        continue;
      }

      final jsonStart = _indexOfJsonStart(remaining);
      if (jsonStart == -1) break;
      if (jsonStart > 0) {
        remaining = remaining.substring(jsonStart);
      }

      final balanced = _extractBalancedJson(remaining);
      if (balanced == null) break;

      if (_isValidJson(balanced)) {
        results.add(balanced);
      }
      remaining = remaining.substring(balanced.length);
    }

    return results;
  }

  static int _indexOfJsonStart(String text) {
    final obj = text.indexOf('{');
    final arr = text.indexOf('[');
    return switch ((obj, arr)) {
      (-1, -1) => -1,
      (-1, _) => arr,
      (_, -1) => obj,
      (_, _) => obj < arr ? obj : arr,
    };
  }

  static bool _isValidJson(String text) {
    try {
      jsonDecode(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  static final _markdownPattern = RegExp(
    r'```(?:json|dart)?\s*([\s\S]*?)\s*```',
  );

  static String? _extractBalancedJson(String input) {
    if (input.isEmpty) return null;
    final opener = input[0];
    if (opener != '{' && opener != '[') return null;
    final closer = opener == '{' ? '}' : ']';

    var balance = 0;
    var inString = false;
    var isEscaped = false;

    for (var i = 0; i < input.length; i++) {
      final char = input[i];

      if (isEscaped) {
        isEscaped = false;
        continue;
      }
      if (char == r'\') {
        isEscaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (!inString) {
        if (char == opener) balance++;
        if (char == closer) {
          balance--;
          if (balance == 0) {
            return input.substring(0, i + 1);
          }
        }
      }
    }
    return null;
  }
}
