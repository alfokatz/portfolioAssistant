import 'package:genui/genui.dart';

/// Comprueba si una surface GenUI tiene componentes listos para renderizar.
abstract final class GenUiSurfaceReadiness {
  static bool hasRootComponent(SurfaceDefinition? definition) {
    return definition != null && definition.components.containsKey('root');
  }

  static Future<void> waitForRootComponent({
    required SurfaceController controller,
    required String surfaceId,
    int maxAttempts = 150,
    Duration pollInterval = const Duration(milliseconds: 20),
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (hasRootComponent(controller.registry.getSurface(surfaceId))) {
        return;
      }
      await Future<void>.delayed(pollInterval);
    }
    throw StateError(
      'La IA no generó una interfaz válida. Intentá reformular la consulta.',
    );
  }
}
