import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart' show A2uiMessage;
import 'package:genui/genui.dart';

/// Aplica líneas A2UI normalizadas al [controller] de forma síncrona.
///
/// Evita la carrera del pipeline asíncrono de [A2uiTransportAdapter.addChunk].
abstract final class A2uiControllerDispatch {
  static void dispatchNormalized(SurfaceController controller, String normalized) {
    for (final line in normalized.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final map = jsonDecode(trimmed) as Map<String, dynamic>;
      // Un mensaje inválido (A2uiValidationError, surface duplicada…) se
      // re-tira como StateError: es el error que `_finishTurn` reintenta.
      // Antes escapaba del retry y terminaba en el "No pude procesar tu
      // consulta" genérico.
      try {
        controller.handleMessage(A2uiMessage.fromJson(map));
      } on StateError {
        rethrow;
      } on Object catch (e) {
        throw StateError('La IA no generó una interfaz válida: $e');
      }
    }
  }
}
