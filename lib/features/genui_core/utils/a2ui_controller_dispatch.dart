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
      controller.handleMessage(A2uiMessage.fromJson(map));
    }
  }
}
