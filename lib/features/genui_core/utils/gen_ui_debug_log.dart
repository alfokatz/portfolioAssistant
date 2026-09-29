import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

/// Logging de diagnóstico para el pipeline GenUI — no hace nada fuera de
/// debug mode.
///
/// Sin esto no había forma de distinguir, para una consulta dada, si el
/// modelo (a) nunca intentó un widget de datos y respondió `QaAnswerText`
/// desde el primer intento, o (b) sí lo intentó y `SurfaceController` lo
/// rechazó por validación (referencia a un widget/id inexistente, tipo no
/// soportado, etc.) — ambos escenarios se ven idénticos desde la UI (texto
/// plano), pero apuntan a fixes distintos (prompt vs. catálogo/schema).
abstract final class GenUiDebugLog {
  static bool _installed = false;

  /// Puentea `genUiLogger` (paquete `genui`) a la consola — por default no
  /// tiene ningún listener, así que sus `warning`/`severe` de validación
  /// (p. ej. "Widget with id: X not found", "Validation failed for surface
  /// ...") se pierden en silencio, sin dejar ningún rastro. Llamar una sola
  /// vez, en `main()`.
  static void installLoggerBridge() {
    if (_installed) return;
    _installed = true;
    genUiLogger.onRecord.listen((record) {
      if (!kDebugMode) return;
      final error = record.error;
      final suffix = error == null ? '' : ' — $error';
      debugPrint('[GenUI/${record.level.name}] ${record.message}$suffix');
    });
  }

  /// El texto crudo que devolvió el modelo para un turno, antes de
  /// sanitizar/normalizar — la única forma de ver qué intentó generar.
  static void rawResponse({required String? surfaceId, required String raw}) {
    if (!kDebugMode) return;
    debugPrint(
      '[GenUI/raw] surface=${surfaceId ?? '(none)'} len=${raw.length}\n$raw',
    );
  }

  /// Resumen id:tipo de los componentes que terminaron dispatcheados para
  /// [surfaceId] — para ver de un vistazo si el modelo eligió un widget de
  /// datos o se quedó en `QaAnswerText`.
  static void componentChoice({
    required String surfaceId,
    required String normalized,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      '[GenUI/choice] surface=$surfaceId '
      'components=${extractComponentTypes(normalized)}',
    );
  }

  /// Parsea las líneas `updateComponents` de [normalized] (una o más
  /// mensajes A2UI separados por salto de línea, como los arma
  /// `A2uiResponseNormalizer`) y devuelve `"id:tipo"` por cada componente.
  /// Público (no solo interno de [componentChoice]) para poder testear la
  /// extracción en sí, sin depender de capturar stdout.
  @visibleForTesting
  static List<String> extractComponentTypes(String normalized) {
    final types = <String>[];
    for (final line in normalized.split('\n')) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map<String, dynamic>) continue;
        final update = decoded['updateComponents'];
        if (update is! Map<String, dynamic>) continue;
        final components = update['components'];
        if (components is! List) continue;
        for (final c in components) {
          if (c is Map && c['id'] != null && c['component'] != null) {
            types.add('${c['id']}:${c['component']}');
          }
        }
      } catch (_) {
        // Best-effort — este log nunca debe romper el flujo real.
      }
    }
    return types;
  }

  /// Qué tools pidió el modelo en una ronda, con qué argumentos, y con qué
  /// `status` volvió cada una — para distinguir "el modelo no pidió el
  /// dato" de "lo pidió y la fuente falló / el plan no lo incluye".
  static void toolRound({
    required int round,
    required List<ToolCallRecord> calls,
  }) {
    if (!kDebugMode) return;
    final summary = calls
        .map((c) => '${c.name}(${jsonEncode(c.args)})→${c.status}')
        .join(', ');
    debugPrint('[GenUI/tools] round=$round $summary');
  }

  /// Una respuesta final que mostraba datos sin la tool que los respalda.
  /// Error de genui que no se puede atribuir al turno actual (de render,
  /// o de otra surface): se ignora en vez de pedirle al modelo que "corrija".
  static void repairIgnored(String currentSurfaceId) {
    if (!kDebugMode) return;
    debugPrint(
      '[GenUI/repair] ignorado: error no atribuible a $currentSurfaceId',
    );
  }

  /// La reescritura pedida perdió la card: se usa la respuesta original.
  static void rewriteDiscarded() {
    if (!kDebugMode) return;
    debugPrint('[GenUI/grounding] reescritura descartada: perdió la card');
  }

  static void answerRejected(String correction) {
    if (!kDebugMode) return;
    debugPrint('[GenUI/grounding] respuesta rechazada: $correction');
  }

  /// `Conversation` reenvía automáticamente cualquier mensaje que
  /// `SurfaceController` publique en `onSubmit` — incluido el que arma tras
  /// un `A2uiValidationException` (ver `SurfaceController.reportError` en
  /// el paquete `genui`), disparando un nuevo `handleSend` sin que la UI se
  /// entere. Sin este log, una validación fallida con auto-retry es
  /// indistinguible de "el modelo nunca intentó nada".
  static void controllerResubmit(ChatMessage message) {
    if (!kDebugMode) return;
    debugPrint(
      '[GenUI/resubmit] auto-retry disparado por SurfaceController.onSubmit '
      '— text="${message.text}" parts=${message.parts.length}',
    );
  }
}
