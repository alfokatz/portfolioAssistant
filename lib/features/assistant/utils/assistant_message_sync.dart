import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/genui_core/utils/llm_json_sanitizer.dart';

/// Mantiene `state.messages` sincronizado con lo que la conversación GenUI
/// terminó resolviendo para un `surfaceId`, incluyendo el caso en que eso
/// pasa DESPUÉS de haber mostrado un error para ese mismo turno.
///
/// `OpenAIGenUiService` reintenta internamente, y el paquete `genui`
/// además dispara su propia auto-resubmisión (no cancelable, no esperada
/// por nadie) cuando la primera respuesta del modelo no valida — así que
/// una surface puede terminar resolviéndose con componentes válidos
/// después de que `AssistantProvider.sendMessage` ya agotó su propia
/// espera y congeló un mensaje de fallback. Estas funciones son las únicas
/// que tocan `List<PortfolioQaMessage>` por `surfaceId`, para que ese caso
/// tardío tenga un único lugar donde "resucitar" el mensaje.
abstract final class AssistantMessageSync {
  /// Reemplaza el placeholder en streaming de [surfaceId] por un mensaje de
  /// fallback en texto plano — nunca deja al usuario sin respuesta ante una
  /// falla de generación (timeout tras reintentar, JSON inválido, etc.).
  /// A diferencia de la versión anterior, CONSERVA el `surfaceId` (marcado
  /// vía [PortfolioQaMessage.isFallback]) en vez de descartarlo: es lo
  /// único que permite que [applySurfaceReady] encuentre este mensaje de
  /// nuevo si un reintento tardío resuelve esa misma surface.
  static List<PortfolioQaMessage> applyFallback(
    List<PortfolioQaMessage> messages,
    String surfaceId,
    AssistantMode engineMode,
  ) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.surfaceId == surfaceId && message.isStreaming) {
        final updated = [...messages];
        updated[i] = message.copyWith(
          isStreaming: false,
          isFallback: true,
          content: LlmJsonSanitizer.defaultFallbackMessage,
        );
        return updated;
      }
    }
    return messages;
  }

  /// Se llama ante CUALQUIER `ConversationComponentsUpdated`/
  /// `ConversationSurfaceAdded` de [surfaceId] — incluyendo uno con
  /// `components: []` o sin `root`, que el modelo puede producir
  /// legítimamente (una generación incompleta/mal formada) y que el
  /// paquete `genui` despacha igual, sin validar nada de su lado. Por eso
  /// [hasRootComponent] es obligatorio acá — la ÚNICA señal de "esto ya es
  /// una respuesta real" es que la propia surface tenga componente raíz,
  /// no simplemente que haya llegado algún evento para ese surfaceId.
  ///
  /// Si [hasRootComponent] es `false`, esto es un no-op: el mensaje sigue
  /// tal cual (streaming, o todavía en fallback) — nunca se marca "listo"
  /// con una surface vacía. Eso deja que el mecanismo que sí tiene un
  /// timeout de verdad (`GenUiRequestTracker.sendAndWait`, o el reintento
  /// interno de `OpenAIGenUiService`) sea quien eventualmente decida
  /// reintentar o caer a [applyFallback] — en vez de que este listener
  /// (que reacciona a CUALQUIER evento, sin timeout propio) se adelante y
  /// congele el mensaje como "listo" mostrando una card en blanco para
  /// siempre.
  ///
  /// Con [hasRootComponent] en `true`: caso normal, el mensaje de ese
  /// turno sigue en streaming → se marca listo. Caso de reintento tardío:
  /// el mensaje ya se había congelado como fallback
  /// ([PortfolioQaMessage.isFallback]) porque la primera espera se agotó —
  /// acá la respuesta real reemplaza al error, nunca al revés. Si el
  /// mensaje ya estaba resuelto (ninguna de las dos cosas), es un no-op.
  static List<PortfolioQaMessage> applySurfaceReady(
    List<PortfolioQaMessage> messages,
    String surfaceId, {
    required bool hasRootComponent,
  }) {
    if (!hasRootComponent) return messages;

    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.surfaceId != surfaceId) continue;

      if (message.isStreaming) {
        final updated = [...messages];
        updated[i] = message.copyWith(isStreaming: false);
        return updated;
      }

      if (message.isFallback) {
        final updated = [...messages];
        updated[i] = message.copyWith(isFallback: false, content: '');
        return updated;
      }

      return messages;
    }
    return messages;
  }
}
