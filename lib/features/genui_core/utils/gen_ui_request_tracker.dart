import 'dart:async';

import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_surface_readiness.dart';

/// Espera la respuesta GenUI tras enviar un mensaje, con timeout.
///
/// Solo completa cuando la [targetSurfaceId] tiene componentes renderizables;
/// no usa [ConversationSurfaceAdded] vacío ni [ConversationContentReceived].
abstract final class GenUiRequestTracker {
  static const defaultTimeout = Duration(seconds: 45);

  static Future<void> sendAndWait({
    required Conversation conversation,
    required String targetSurfaceId,
    required Future<void> Function() send,
    Duration timeout = defaultTimeout,
  }) async {
    final completer = Completer<void>();
    late StreamSubscription<ConversationEvent> subscription;

    subscription = conversation.events.listen((event) {
      if (completer.isCompleted) return;
      switch (event) {
        case ConversationSurfaceAdded(:final surfaceId, :final definition):
          if (surfaceId == targetSurfaceId &&
              GenUiSurfaceReadiness.hasRootComponent(definition)) {
            completer.complete();
          }
        case ConversationComponentsUpdated(:final surfaceId, :final definition):
          if (surfaceId == targetSurfaceId &&
              GenUiSurfaceReadiness.hasRootComponent(definition)) {
            completer.complete();
          }
        case ConversationError(:final error):
          completer.completeError(error);
        default:
          break;
      }
    });

    try {
      // `send()` incluye el consumo del stream de OpenAI, que no tiene
      // timeout propio (a diferencia de las llamadas no-streaming del SDK).
      // Por eso el timeout debe cubrir `send()` y no solo la espera del
      // completer: si el stream se cuelga, `send()` nunca resuelve y el
      // timeout de abajo nunca se alcanzaría.
      await Future.wait<void>([
        send(),
        completer.future,
      ]).timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'La IA no generó una interfaz a tiempo. Revisá tu conexión o intentá de nuevo.',
        ),
      );
    } finally {
      await subscription.cancel();
    }
  }
}
