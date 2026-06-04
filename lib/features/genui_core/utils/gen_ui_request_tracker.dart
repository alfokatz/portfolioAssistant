import 'dart:async';

import 'package:genui/genui.dart';

/// Espera la respuesta GenUI tras enviar un mensaje, con timeout.
///
/// Solo completa cuando la [targetSurfaceId] recibe surface o componentes;
/// no usa [ConversationContentReceived] genérico (evita falsos positivos y loaders colgados).
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
        case ConversationSurfaceAdded(:final surfaceId):
        case ConversationComponentsUpdated(:final surfaceId):
          if (surfaceId == targetSurfaceId) completer.complete();
        case ConversationError(:final error):
          completer.completeError(error);
        default:
          break;
      }
    });

    try {
      await send();
      await completer.future.timeout(
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
