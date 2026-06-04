import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';

/// Suscripción a eventos de [Conversation] con cancelación segura al reinit/dispose.
final class GenUiConversationSubscription {
  StreamSubscription<ConversationEvent>? _subscription;

  void listen(
    Conversation conversation,
    void Function(ConversationEvent event) onEvent,
  ) {
    _subscription?.cancel();
    _subscription = conversation.events.listen(onEvent);
  }

  void cancel() {
    _subscription?.cancel();
    _subscription = null;
  }
}

/// Actualiza estado de pantalla GenUI según eventos de conversación.
///
/// El loading principal lo controla [sendAndWait]; no activar spinner en
/// [ConversationWaiting] para evitar loaders colgados por eventos tardíos.
abstract final class GenUiFlowScreenHelpers {
  static void handleConversationEvent({
    required ConversationEvent event,
    required VoidCallback onStateChanged,
    required List<String> surfaceIds,
    required void Function(String? error) setError,
    required void Function(bool waiting) setWaiting,
  }) {
    switch (event) {
      case ConversationWaiting():
        break;
      case ConversationError(:final error):
        setError(genUiErrorMessage(error));
        setWaiting(false);
        onStateChanged();
      case ConversationSurfaceAdded(:final surfaceId):
        setWaiting(false);
        if (!surfaceIds.contains(surfaceId)) {
          surfaceIds.add(surfaceId);
        }
        onStateChanged();
      case ConversationComponentsUpdated(:final surfaceId):
        setWaiting(false);
        if (!surfaceIds.contains(surfaceId)) {
          surfaceIds.add(surfaceId);
        }
        onStateChanged();
      case ConversationSurfaceRemoved(:final surfaceId):
        surfaceIds.remove(surfaceId);
        onStateChanged();
      case ConversationContentReceived():
        setWaiting(false);
        onStateChanged();
    }
  }
}
