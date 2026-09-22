import 'dart:async';
import 'dart:convert';

import 'package:dart_openai/dart_openai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/genui_core/genui_surface_ids.dart';
import 'package:portfolio_assistant/features/genui_core/utils/a2ui_controller_dispatch.dart';
import 'package:portfolio_assistant/features/genui_core/utils/a2ui_response_normalizer.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_debug_log.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';
import 'package:portfolio_assistant/features/genui_core/utils/llm_json_sanitizer.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_surface_readiness.dart';
import 'package:portfolio_assistant/features/genui_core/utils/openai_request_throttle.dart';

export 'package:portfolio_assistant/features/genui_core/genui_surface_ids.dart';

/// Servicio GenUI con streaming OpenAI y transporte A2UI.
///
/// Por defecto usa [defaultModel] (`gpt-4.1-mini`) por buen balance
/// precio/calidad en JSON A2UI.
/// Override opcional: `OPENAI_MODEL` en `.env`.
class OpenAIGenUiService {
  static const defaultModel = 'gpt-4.1-mini';
  static const maxRateLimitRetries = 3;

  // Reintento corto para fallas transitorias que NO son rate-limit: el
  // stream se colgó (timeout interno de streamCompletion) o el modelo
  // produjo un payload que, ya reparado, seguía sin componente raíz. Un
  // solo reintento adicional, separado del budget de rate-limit.
  static const maxTransientRetries = 1;
  static const _transientRetryBackoff = Duration(milliseconds: 600);

  // Techo absoluto por intento de streaming — no es un timeout de Stream
  // (que resetea con cada chunk), sino un techo de tiempo total desde que
  // arranca el intento, para poder abandonar un stream colgado y
  // reintentar en vez de depender solo del timeout externo de
  // GenUiRequestTracker.
  static const _streamTimeout = Duration(seconds: 24);

  OpenAIGenUiService({
    String? apiKey,
    String? model,
    required this.systemPrompt,
    required Catalog catalog,
    this.a2uiSurfaceId,
    this.a2uiCatalogId,
  })  : apiKey = apiKey ?? dotenv.env['OPENAI_API_KEY'] ?? '',
        model = model ?? dotenv.env['OPENAI_MODEL'] ?? defaultModel {
    OpenAI.apiKey = this.apiKey;
    controller = SurfaceController(catalogs: [catalog]);
    transport = A2uiTransportAdapter(onSend: handleSend);
    conversation = Conversation(
      controller: controller,
      transport: transport,
    );
    // `Conversation` ya escucha `controller.onSubmit` para reenviar
    // automáticamente cualquier mensaje que el controller publique ahí
    // (incluido el que arma tras una validación fallida — ver
    // `GenUiDebugLog.controllerResubmit`); esta segunda suscripción es solo
    // para loguearlo, no cambia el comportamiento (`onSubmit` es un stream
    // broadcast).
    _debugResubmitSubscription = controller.onSubmit.listen(
      GenUiDebugLog.controllerResubmit,
    );
    history.add(
      OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.system,
        content: [
          OpenAIChatCompletionChoiceMessageContentItemModel.text(systemPrompt),
        ],
      ),
    );
  }

  final String apiKey;
  final String model;
  final String systemPrompt;
  final String? a2uiSurfaceId;
  final String? a2uiCatalogId;
  late final SurfaceController controller;
  late final A2uiTransportAdapter transport;
  late final Conversation conversation;
  final List<OpenAIChatCompletionChoiceMessageModel> history = [];
  String? _runtimeSurfaceId;
  // Igual que `a2uiSurfaceId` pero mutable: se actualiza en cada llamada
  // EXPLÍCITA a `handleSend` (un turno real, con `surfaceId` pasado a
  // mano) y sirve de fallback cuando `handleSend` se dispara solo, sin
  // `surfaceId` — el auto-retry que arma `SurfaceController.reportError`
  // tras una validación fallida, o un evento de UI (`handleUiEvent`),
  // ambos vía `Conversation.onSubmit` → `A2uiTransportAdapter.sendRequest`
  // → acá (ver `handleSend`). Sin esto, esas dos llamadas resolvían
  // `surfaceId: null` y lo que devolvían nunca se despachaba a ningún
  // surface — se perdía en silencio, indistinguible desde la UI de "el
  // modelo nunca intentó nada".
  String? _lastKnownSurfaceId;
  bool isDisposed = false;
  StreamSubscription<ChatMessage>? _debugResubmitSubscription;

  String? get _effectiveSurfaceId => _runtimeSurfaceId ?? a2uiSurfaceId;

  @Deprecated('Use GenUiSurfaceIds.portfolioAnalysis')
  static const analysisSurfaceId = GenUiSurfaceIds.portfolioAnalysis;

  static const investmentSurfaceId = GenUiSurfaceIds.investmentDecision;

  Future<void> handleSend(
    ChatMessage message, {
    String? surfaceId,
  }) async {
    if (surfaceId != null) _lastKnownSurfaceId = surfaceId;
    _runtimeSurfaceId = surfaceId ?? _lastKnownSurfaceId;
    try {
      var userText = message.text.trim();

      // `SurfaceController.handleUiEvent`/`.reportError` (paquete genui)
      // reenvían acá vía `onSubmit` con `text` vacío y el contenido real
      // en `parts` (un `UiInteractionPart` con JSON crudo) — antes eso se
      // perdía en silencio: ni el modelo se enteraba de qué había que
      // corregir, ni `history` quedaba con rastro de que algo había
      // pasado. `_describeInteraction` lo convierte en una instrucción
      // legible para el modelo.
      if (userText.isEmpty) {
        final interactions = message.parts.uiInteractionParts;
        if (interactions.isNotEmpty) {
          userText = _describeInteraction(interactions.first.interaction);
        }
      }

      if (userText.isEmpty && message.parts.isEmpty) return;

      if (userText.isNotEmpty) {
        history.add(
          OpenAIChatCompletionChoiceMessageModel(
            role: OpenAIChatMessageRole.user,
            content: [
              OpenAIChatCompletionChoiceMessageContentItemModel.text(userText),
            ],
          ),
        );
      }

      if (apiKey.isEmpty) {
        throw StateError('OPENAI_API_KEY no configurada');
      }

      // `transientAttempts` es un budget aparte del de rate-limit: cubre
      // el timeout interno del stream (streamCompletion colgado) y el
      // StateError de "interfaz inválida" — ambas son fallas de
      // generación, no de conexión, y el mensaje del usuario ya se agregó
      // a `history` una sola vez arriba, así que reintentar acá adentro
      // no lo duplica en el historial que le mandamos a OpenAI.
      var transientAttempts = 0;
      for (var attempt = 0; attempt <= maxRateLimitRetries; attempt++) {
        try {
          await streamCompletion();
          return;
        } on RequestFailedException catch (e) {
          final canRetry =
              isOpenAiRateLimitError(e) && attempt < maxRateLimitRetries;
          if (!canRetry || isDisposed) rethrow;
          final seconds = openAiSuggestedRetrySeconds(e.message) ?? 5;
          await Future<void>.delayed(
            Duration(milliseconds: ((seconds + 1) * 1000).clamp(2000, 120000)),
          );
        } on TimeoutException {
          if (isDisposed || transientAttempts >= maxTransientRetries) rethrow;
          transientAttempts++;
          await Future<void>.delayed(_transientRetryBackoff);
        } on StateError {
          if (isDisposed || transientAttempts >= maxTransientRetries) rethrow;
          transientAttempts++;
          await Future<void>.delayed(_transientRetryBackoff);
        }
      }
    } finally {
      _runtimeSurfaceId = null;
    }
  }

  /// Convierte el JSON crudo de un `UiInteractionPart` (ver `handleSend`)
  /// en una instrucción legible. Distingue el caso de error de validación
  /// (`{"error": {...}}`, armado por `SurfaceController.reportError`) —
  /// que es el único que este servicio dispara hoy, ya que el catálogo de
  /// la app no emite eventos de UI (`handleUiEvent`) — y para cualquier
  /// otra forma reenvía el JSON tal cual, en vez de asumir su estructura.
  static String _describeInteraction(String interactionJson) {
    try {
      final decoded = jsonDecode(interactionJson);
      if (decoded is Map && decoded['error'] is Map) {
        final error = decoded['error'] as Map;
        final message =
            error['message'] as String? ?? 'la interfaz no pudo renderizarse.';
        return 'ERROR DE VALIDACIÓN en tu última respuesta para este '
            'surface: $message Corregí la interfaz: usá solo ids que ya '
            'definiste vos mismo (o que ya existen) y tipos de componente '
            'que estén en el catálogo, y volvé a emitir createSurface + '
            'updateComponents completos para este mismo surface.';
      }
    } catch (_) {
      // Best-effort — si no es JSON o no tiene la forma esperada, se
      // reenvía tal cual abajo.
    }
    return interactionJson;
  }

  Future<void> _consumeStream(
    Stream<OpenAIStreamChatCompletionModel> stream,
    StringBuffer modelBuffer,
  ) async {
    await for (final chunk in stream) {
      if (isDisposed) break;
      final delta = chunk.choices.firstOrNull?.delta.content;
      if (delta == null || delta.isEmpty) continue;
      final chunkText = delta.firstOrNull?.text;
      if (chunkText == null || chunkText.isEmpty) continue;
      modelBuffer.write(chunkText);
    }
  }

  Future<void> streamCompletion() async {
    await OpenAiRequestThrottle.waitIfNeeded();
    OpenAiRequestThrottle.markRequestStarted();

    final modelBuffer = StringBuffer();
    // NO responseFormat: json_object acá — el protocolo A2UI que arma
    // `genui` (SurfaceOperations.createAndUpdate) le pide al modelo emitir
    // DOS mensajes JSON de alto nivel separados (createSurface, luego
    // updateComponents), incluso envueltos en fences de markdown. El modo
    // json_object de OpenAI obliga a que la respuesta completa sea
    // exactamente UN objeto JSON válido — no puede emitir dos objetos
    // concatenados ni markdown. Probado en vivo: con el flag activo,
    // createSurface se pierde y updateComponents apunta a una superficie
    // que nunca se creó, así que toda consulta cae al fallback de texto.
    final stream = OpenAI.instance.chat.createStream(
      model: model,
      messages: history,
      temperature: 0.35,
    );

    // Techo absoluto por intento (no por gap entre chunks) — si el stream
    // se cuelga, esto lo convierte en una excepción catcheable por el
    // retry loop de `handleSend` en vez de un colgado eterno.
    await _consumeStream(stream, modelBuffer).timeout(
      _streamTimeout,
      onTimeout: () => throw TimeoutException(
        'El modelo tardó demasiado en responder.',
      ),
    );

    if (isDisposed) return;

    final raw = modelBuffer.toString();
    final surfaceId = _effectiveSurfaceId;
    final catalogId = a2uiCatalogId ?? A2uiResponseNormalizer.defaultCatalogId;
    GenUiDebugLog.rawResponse(surfaceId: surfaceId, raw: raw);

    var cleaned = surfaceId != null
        ? LlmJsonSanitizer.sanitizeOrFallback(
            raw,
            surfaceId: surfaceId,
            catalogId: catalogId,
          )
        : (raw.isEmpty ? '' : LlmJsonSanitizer.sanitize(raw));

    if (cleaned.isEmpty && surfaceId != null) {
      cleaned = A2uiResponseNormalizer.fallbackResponse(
        surfaceId,
        LlmJsonSanitizer.defaultFallbackMessage,
        catalogId: catalogId,
      );
    }

    if (cleaned.isEmpty) return;

    if (surfaceId != null) {
      final normalized = A2uiResponseNormalizer.normalize(
        cleaned,
        surfaceId: surfaceId,
        catalogId: catalogId,
      );
      cleaned = normalized.trim().isEmpty
          ? A2uiResponseNormalizer.fallbackResponse(
              surfaceId,
              LlmJsonSanitizer.defaultFallbackMessage,
              catalogId: catalogId,
            )
          : normalized;
    }

    if (surfaceId != null) {
      GenUiDebugLog.componentChoice(surfaceId: surfaceId, normalized: cleaned);
    }
    A2uiControllerDispatch.dispatchNormalized(controller, cleaned);

    if (surfaceId != null &&
        !GenUiSurfaceReadiness.hasRootComponent(
          controller.registry.getSurface(surfaceId),
        )) {
      throw StateError(
        'La IA no generó una interfaz válida. Intentá reformular la consulta.',
      );
    }

    history.add(
      OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.assistant,
        content: [
          OpenAIChatCompletionChoiceMessageContentItemModel.text(raw),
        ],
      ),
    );
  }

  void dispose() {
    isDisposed = true;
    _debugResubmitSubscription?.cancel();
    conversation.dispose();
    transport.dispose();
    controller.dispose();
  }
}
